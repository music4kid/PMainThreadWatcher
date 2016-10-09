//
//  PMainThreadWatcher.h
//  UIThreadWatcher
//
//  Created by gao feng on 2016/10/8.
//  Copyright © 2016年 music4kid. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PMainThreadWatcherDelegate <NSObject>

- (void)onMainThreadSlowStackDetected:(NSArray*)slowStack;

@end

@interface PMainThreadWatcher : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, weak) id<PMainThreadWatcherDelegate>     watchDelegate;


//must be called from main thread
- (void)startWatch;

@end
