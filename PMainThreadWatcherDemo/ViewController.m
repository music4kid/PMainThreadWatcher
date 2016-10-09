//
//  ViewController.m
//  PMainThreadWatcherDemo
//
//  Created by gao feng on 2016/10/9.
//  Copyright © 2016年 music4kid. All rights reserved.
//

#import "ViewController.h"
#import "PMainThreadWatcher.h"

@interface ViewController () <PMainThreadWatcherDelegate>
@property (nonatomic, strong) NSTimer*                 busyJobTimer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [PMainThreadWatcher sharedInstance].watchDelegate = self;
    [[PMainThreadWatcher sharedInstance] startWatch];
    
    self.busyJobTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(onBusyJobTimeout) userInfo:nil repeats:true];
}

- (void)onBusyJobTimeout
{
    [self doBusyJob];
}

- (void)doBusyJob
{
    int logCount = 10000;
    for (int i = 0; i < logCount; i ++) {
        NSLog(@"busy...\n");
    }
}

- (void)onMainThreadSlowStackDetected:(NSArray*)slowStack {
	
    NSLog(@"current thread: %@\n", [NSThread currentThread]);
    
    NSLog(@"===begin printing slow stack===\n");
    for (NSString* call in slowStack) {
        NSLog(@"%@\n", call);
    }
    NSLog(@"===end printing slow stack===\n");
}




@end

