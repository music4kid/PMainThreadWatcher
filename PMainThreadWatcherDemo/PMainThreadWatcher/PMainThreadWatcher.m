//
//  PMainThreadWatcher.m
//  UIThreadWatcher
//
//  Created by gao feng on 2016/10/8.
//  Copyright © 2016年 music4kid. All rights reserved.
//

#import "PMainThreadWatcher.h"

#define PMainThreadWatcher_Watch_Interval     1.0f
#define PMainThreadWatcher_Warning_Level     (16.0f/1000.0f)

#define Notification_PMainThreadWatcher_Worker_Ping    @"Notification_PMainThreadWatcher_Worker_Ping"
#define Notification_PMainThreadWatcher_Main_Pong    @"Notification_PMainThreadWatcher_Main_Pong"

#include <signal.h>
#include <pthread.h>

#define CALLSTACK_SIG SIGUSR1
static pthread_t mainThreadID;

#include <libkern/OSAtomic.h>
#include <execinfo.h>

static void thread_singal_handler(int sig)
{
    NSLog(@"main thread catch signal: %d", sig);
    
    if (sig != CALLSTACK_SIG) {
        return;
    }
    
    NSArray* callStack = [NSThread callStackSymbols];
    
    id<PMainThreadWatcherDelegate> del = [PMainThreadWatcher sharedInstance].watchDelegate;
    if (del != nil && [del respondsToSelector:@selector(onMainThreadSlowStackDetected:)]) {
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

static void install_signal_handler()
{
    signal(CALLSTACK_SIG, thread_singal_handler);
}

static void printMainThreadCallStack()
{
    NSLog(@"sending signal: %d to main thread", CALLSTACK_SIG);
    pthread_kill(mainThreadID, CALLSTACK_SIG);
}


dispatch_source_t createGCDTimer(uint64_t interval, uint64_t leeway, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_walltime(NULL, interval), interval, leeway);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
    return timer;
}


@interface PMainThreadWatcher ()
@property (nonatomic, strong) dispatch_source_t                 pingTimer;
@property (nonatomic, strong) dispatch_source_t                 pongTimer;
@end

@implementation PMainThreadWatcher

+ (instancetype)sharedInstance
{
    static PMainThreadWatcher* instance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [PMainThreadWatcher new];
    });

    return instance;
}

- (void)startWatch {
    
    if ([NSThread isMainThread] == false) {
        NSLog(@"Error: startWatch must be called from main thread!");
        return;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(detectPingFromWorkerThread) name:Notification_PMainThreadWatcher_Worker_Ping object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(detectPongFromMainThread) name:Notification_PMainThreadWatcher_Main_Pong object:nil];
    
    install_signal_handler();
    
    mainThreadID = pthread_self();
    
    //ping from worker thread
    uint64_t interval = PMainThreadWatcher_Watch_Interval * NSEC_PER_SEC;
    self.pingTimer = createGCDTimer(interval, interval / 10000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self pingMainThread];
    });
}

- (void)pingMainThread
{
    uint64_t interval = PMainThreadWatcher_Warning_Level * NSEC_PER_SEC;
    self.pongTimer = createGCDTimer(interval, interval / 10000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self onPongTimeout];
    });
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:Notification_PMainThreadWatcher_Worker_Ping object:nil];
    });
}

- (void)detectPingFromWorkerThread
{
    [[NSNotificationCenter defaultCenter] postNotificationName:Notification_PMainThreadWatcher_Main_Pong object:nil];
}

- (void)onPongTimeout
{
    [self cancelPongTimer];
    printMainThreadCallStack();
}

- (void)detectPongFromMainThread
{
    [self cancelPongTimer];
}

- (void)cancelPongTimer
{
    if (self.pongTimer) {
        dispatch_source_cancel(_pongTimer);
        _pongTimer = nil;
    }
}

@end
