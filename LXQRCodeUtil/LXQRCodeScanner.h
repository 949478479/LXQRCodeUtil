//
//  LXQRCodeScanner.h
//  LXQRCodeUtil_demo
//
//  Created by 从今以后 on 2017/5/25.
//  Copyright © 2017年 从今以后. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LXCaptureVideoPreviewView : UIView

/// 默认为 0.25
@property (nonatomic) IBInspectable CGFloat maskAlpha;

@end


@interface LXQRCodeScanner : NSObject 

/// 取值范围 0.0 ~ 1.0，默认为 { 0.0 , 0.0, 1.0, 1.0 }
@property (nonatomic) IBInspectable CGRect rectOfInterest;
@property (null_resettable, nonatomic, readonly) IBOutlet LXCaptureVideoPreviewView *previewView;

@property (nullable, nonatomic) void (^failureBlock)(NSError *error);
@property (nullable, nonatomic) void (^completionBlock)(LXQRCodeScanner *scanner, NSArray<NSString *> *messages);

- (void)startRunningWithCallback:(void (^)(void))callback;
- (void)stopRunningWithCallback:(void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
