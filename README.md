iOS设备虽然在硬件和软件层面一直在优化，但还是有不少坑会导致UI线程的卡顿。对于程序员来说，除了增加自身知识储备和养成良好的编程习惯之外，如果能一套机制能自动预报“卡顿”并检测出导致该“卡顿”的代码位置自然更好。本文就可能的实现方案做一些探讨和分析。先贴出[最后方案的github地址](https://github.com/music4kid/PMainThreadWatcher)。

#### 解决方案分析

简单来说，主线程为了达到接近60fps的绘制效率，不能在UI线程有单个超过（1/60s≈16ms）的计算任务。通过Instrument设置16ms的采样率可以检测出大部分这种费时的任务，但有以下缺点：

1. Instrument profile一次重新编译，时间较长。
2. 只能针对特定的操作场景进行检测，要预先知道卡顿产生的场景。
3. 每次猜测，更改，再猜测再以此循环，需要重新profile。

我们的目标方案是，检测能够自动发生，并不需要开发人员做任何预先配置或profile。运行时发现卡顿能即时通知开发人员导致卡顿的函数调用栈。

基于上述前提，我暂时能想到两个方案大致可行。

#### 方案一：基于Runloop

主线程绝大部分计算或者绘制任务都是以Runloop为单位发生。单次Runloop如果时长超过16ms，就会导致UI体验的卡顿。那如何检测单次Runloop的耗时呢？

Runloop的生命周期及运行机制虽然不透明，但苹果提供了一些API去检测部分行为。我们可以通过如下代码监听Runloop每次进入的事件：

```
- (void)setupRunloopObserver
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFRunLoopRef runloop = CFRunLoopGetCurrent();
        
        CFRunLoopObserverRef enterObserver;
        enterObserver = CFRunLoopObserverCreate(CFAllocatorGetDefault(),
                                               kCFRunLoopEntry | kCFRunLoopExit,
                                               true,
                                               -0x7FFFFFFF,
                                               BBRunloopObserverCallBack, NULL);
        CFRunLoopAddObserver(runloop, enterObserver, kCFRunLoopCommonModes);
        CFRelease(enterObserver);
    });
}

static void BBRunloopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    switch (activity) {
        case kCFRunLoopEntry: {
            NSLog(@"enter runloop...");
        }
            break;
        case kCFRunLoopExit: {
            NSLog(@"leave runloop...");
        }
            break;
        default: break;
    }
}
```

看起来kCFRunLoopExit的时间，减去kCFRunLoopEntry的时间，即为一次Runloop所耗费的时间。这个方案我并没有继续深入思考更多的细节。因为虽然能找出大于16ms的runloop，但无法定位到具体的函数，只能起到预报的作用，不符合我们的目标方案。

#### 方案二：基于线程

最理想的方案是让UI线程“主动汇报”当前耗时的任务，听起来简单做起来不轻松。

我们可以假设这样一套机制：每隔16ms让UI线程来报道一次，如果16ms之后UI线程没来报道，那就一定是在执行某个耗时的任务。这种抽象的描述翻译成代码，可以用如下表述：

**我们启动一个worker线程，worker线程每隔一小段时间（delta）ping以下主线程（发送一个NSNotification），如果主线程此时有空，必然能接收到这个通知，并pong以下（发送另一个NSNotification），如果worker线程超过delta时间没有收到pong的回复，那么可以推测UI线程必然在处理其他任务了，此时我们执行第二步操作，暂停UI线程，并打印出当前UI线程的函数调用栈。**

难点在这第二步，如何暂停UI线程，同时获取到callstack。

iOS的多线程编程一般使用NSOperation或者GCD，这两者都无法暂停每个正在执行的线程。所谓的cancel调用也只能在目标线程空闲的时候，主动检测cancelled状态，然后主动sleep，这显然非我所欲。

还剩下pthread一途，pthread系列api当中有个函数pthread_kill()看起来符合期望。

> The pthread_kill() function sends the signal sig to thread, a thread in the same process as the caller.  The signal is asynchronously directed to thread.
>  If sig is 0, then no signal is sent, but error checking is still performed.

如果我们从worker线程给UI线程发送signal，UI线程会被即刻暂停，并进入接收signal的回调，再将callstack打印就接近目标了。

iOS确实允许在主线程注册一个signal处理函数，类似这样：

```
signal(CALLSTACK_SIG, thread_singal_handler);
```

这里补充下signal相关的知识点。

iOS系统的signal可以被归为两类：

第一类内核signal，这类signal由操作系统内核发出，比如当我们访问VM上不属于自己的内存地址时，会触发EXC_BAD_ACCESS异常，内核检测到该异常之后会发出第二类signal：BSD signal，传递给应用程序。

第二类BSD signal，这类signal需要被应用程序自己处理。通常当我们的App进程运行时遇到异常，比如NSArray越界访问。产生异常的线程会向当前进程发出signal，如果这个signal没有别处理，我们的app就会crash了。

平常我们调试的时候很容易遇到第二类signal导致整个程序被中断的情况，gdb同时会将每个线程的调用栈呈现出来。

pthread_kill允许我们向目标线程（UI线程）发送signal，目标线程被暂停，同时进入signal回调，将当前线程的callstack获取并处理，处理完signal之后UI线程继续运行。将callstack打印即可精确定位产生问题的函数调用栈。

#### 代码流程

理清思路之后实现起来就比较简单了。

在主线程注册signal handler

```
signal(CALLSTACK_SIG, thread_singal_handler);
```

通过NSNotification完成ping pong流程

```
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(detectPingFromWorkerThread) name:Notification_PMainThreadWatcher_Worker_Ping object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(detectPongFromMainThread) name:Notification_PMainThreadWatcher_Main_Pong object:nil];
```

如果ping超时，pthread_kill主线程。

```
pthread_kill(mainThreadID, CALLSTACK_SIG);
```

主线程被暂停，进入signal回调，通过[NSThread callStackSymbols]获取主线程当前callstack。

```
static void thread_singal_handler(int sig)
{
    NSLog(@"main thread catch signal: %d", sig);
    
    if (sig != CALLSTACK_SIG) {
        return;
    }
    
    NSArray* callStack = [NSThread callStackSymbols];
    
    id<PMainThreadWatcherDelegate> del = [PMainThreadWatcher sharedInstance].watchDelegate;
    if (del != nil && [del respondsToSelector:@selector(onMainThreadSlowStackDetected:)])          
    {
        [del onMainThreadSlowStackDetected:callStack];
    }
    else
    {
        NSLog(@"detect slow call stack on main thread! \n");
        for (NSString* call in callStack) {
            NSLog(@"%@\n", call);
        }
    }
    
    return;
}
```

至此基础流程结束。值得一提的是上述代码不能调试，因为调试时gdb会干扰signal的处理，导致signal handler无法进入。

感兴趣的朋友可以查看完整的[demo代码](https://github.com/music4kid/PMainThreadWatcher)。

#### 后期任务

后面我会尝试继续完善上述代码，处理更多的边界情况，并将一些参数做到可配置，期望将其改造成可用的一个小工具。

欢迎关注公众号：

<img src="http://mrpeak.cn/images/qr.jpg" width="150">
