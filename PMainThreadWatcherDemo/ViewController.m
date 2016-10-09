//
//  ViewController.m
//  PMainThreadWatcherDemo
//
//  Created by gao feng on 2016/10/9.
//  Copyright © 2016年 music4kid. All rights reserved.
//

#import "ViewController.h"
#import "PMainThreadWatcher.h"

@interface ViewController ()
@property (nonatomic, strong) NSTimer*                 busyJobTimer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
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


@end

