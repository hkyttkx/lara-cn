//
//  Ace.h  —  王牌战争 ESP
//
//  用法（Swift）:
//      AceESP.shared().logBlock = { print($0) }
//      AceESP.shared().start()
//
#ifndef ACE_H
#define ACE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 实现文件里要用到的 C 标准库（避免隐式声明报错）
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface AceESP : NSObject

+ (instancetype)shared;

/// 进程名（用 lara 的进程列表确认后改）
@property (nonatomic, copy) NSString *targetProcess;

/// 启动：跑内核 → 连进程 → 解析 il2cpp → 装 overlay → 开扫描循环
- (BOOL)start;

/// 停止并清理 overlay
- (void)stop;

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSUInteger lastPlayerCount;
@property (nonatomic, copy, nullable) void (^logBlock)(NSString *line);

@end

NS_ASSUME_NONNULL_END

#endif /* ACE_H */
