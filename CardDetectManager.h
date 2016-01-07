//
//  CardDetectManager.h
//  HHMobileOfficeIOS
//
//  Created by zhengqiwen on 15/11/16.
//  Copyright © 2015年 admin. All rights reserved.
//

#import <Foundation/Foundation.h>


@class MessageController;

@interface CardDetectManager : NSObject

@property (nonatomic,assign) BOOL isFromMessageModel;//是否是从消息模块调用

- (void)beginTakePhoto:(MessageController *)presentVC;//开始拍照



@end
