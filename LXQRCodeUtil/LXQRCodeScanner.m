//
//  LXQRCodeScanner.m
//  LXQRCodeUtil_demo
//
//  Created by 从今以后 on 2017/5/25.
//  Copyright © 2017年 从今以后. All rights reserved.
//

#import "LXQRCodeScanner.h"

#ifdef DEBUG
#define LXLog(format, ...) \
printf("%s at %s:%d %s\n", \
__FUNCTION__, \
(strrchr(__FILE__, '/') ?: __FILE__ - 1) + 1, \
__LINE__, \
[[NSString stringWithFormat:(format), ##__VA_ARGS__] UTF8String])
#else
#define LXLog(format, ...)
#endif

@interface LXCaptureVideoPreviewView ()
@property (nonatomic) CGRect rectOfInterest;
@property (nonatomic) CAShapeLayer *maskLayer;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation LXCaptureVideoPreviewView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _maskAlpha = 0.25;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _maskAlpha = 0.25;
    }
    return self;
}

- (void)layoutSublayersOfLayer:(CALayer *)layer
{
    [super layoutSublayersOfLayer:layer];
    
    self.previewLayer.frame = self.bounds;
    
    if (!CGRectEqualToRect(self.maskLayer.bounds, self.bounds)) {
        [self _adjustMaskLayer];
    }
}

- (void)_adjustMaskLayer
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    [self.maskLayer removeFromSuperlayer];
    
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGRect rect = {
        self.rectOfInterest.origin.x * width,
        self.rectOfInterest.origin.y * height,
        self.rectOfInterest.size.width * width,
        self.rectOfInterest.size.height * height,
    };
    
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, self.bounds);
    CGPathAddRect(path, NULL, rect);
    
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = self.bounds;
    maskLayer.opacity = self.maskAlpha;
    maskLayer.path = CFAutorelease(path);
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    
    [self.layer addSublayer:maskLayer];
    
    [CATransaction commit];
}

- (void)setPreviewLayer:(AVCaptureVideoPreviewLayer *)previewLayer
{
    if (self.previewLayer != previewLayer) {
        [self.previewLayer removeFromSuperlayer];
        _previewLayer = previewLayer;
        [self.layer insertSublayer:previewLayer atIndex:0];
    }
}

- (void)setMaskAlpha:(CGFloat)maskAlpha
{
    _maskAlpha = maskAlpha;
    self.maskLayer.opacity = maskAlpha;
}

@end

@interface LXQRCodeScanner () <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic) dispatch_queue_t serialQueue;

@property (nonatomic) AVCaptureDevice *device;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *input;
@property (nonatomic) AVCaptureMetadataOutput *output;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic) void (^didStartRunningCallback)(void);
@property (nonatomic) void (^didStopRunningCallback)(void);

@end

@implementation LXQRCodeScanner
@synthesize previewView = _previewView;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 初始化

- (instancetype)init
{
    self = [super init];
    if (self) {
        _session = [AVCaptureSession new];
        _rectOfInterest = CGRectMake(0, 0, 1, 1);
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
        _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        _serialQueue = dispatch_queue_create("com.hereafter.QRCodeSerialQueue", 0);
        
        [self _registerSessionRunningNotification];
    }
    return self;
}

#pragma mark - 启动 & 停止

- (void)startRunningWithCallback:(void (^)(void))callback
{
    if (self.session.isRunning) {
        return;
    }
    
    _didStartRunningCallback = callback;
    
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                dispatch_async(self.serialQueue, ^{
                    if (!self.session.isRunning && [self _addDeviceInput]) {
                        [self _addMetadataOutput];
                        [self _configureDevice];
                        [self.session startRunning];
                    }
                });
            } else {
                NSDictionary *userInfo = @{ NSLocalizedFailureReasonErrorKey: @"The user has denied this application permission for media capture." };
                NSError *error = [NSError errorWithDomain:AVFoundationErrorDomain
                                                     code:AVErrorApplicationIsNotAuthorizedToUseDevice
                                                 userInfo:userInfo];
                !self.failureBlock ?: self.failureBlock(error);
            }
        });
    }];
}

- (void)stopRunningWithCallback:(void (^)(void))callback
{
    if (!self.session.isRunning) {
        return;
    }
    _didStopRunningCallback = callback;
    dispatch_async(self.serialQueue, ^{
        [self.session stopRunning];
    });
}

#pragma mark - 配置

- (void)setPreviewView:(LXCaptureVideoPreviewView *)previewView
{
    if (_previewView != previewView) {
        _previewView = previewView;
        _previewView.previewLayer = self.previewLayer;
    }
}

- (LXCaptureVideoPreviewView *)previewView
{
    if (!_previewView) {
        self.previewView = [LXCaptureVideoPreviewView new];
    }
    return _previewView;
}

- (void)setRectOfInterest:(CGRect)rectOfInterest
{
    _rectOfInterest = rectOfInterest;

    self.previewView.rectOfInterest = rectOfInterest;
    self.output.rectOfInterest = (CGRect){
        rectOfInterest.origin.y,
        rectOfInterest.origin.x,
        rectOfInterest.size.height,
        rectOfInterest.size.width,
    };
}

- (BOOL)_addDeviceInput
{
    if (self.input) {
        return YES;
    }
    
    NSError *error = nil;
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
    if (!error) {
        [self.session addInput:self.input];
        return YES;
    }
    
    !self.failureBlock ?: self.failureBlock(error);
    
    return NO;
}

- (void)_addMetadataOutput
{
    if (self.output) {
        return;
    }
    self.output = [AVCaptureMetadataOutput new];
    [self.session addOutput:self.output];
    self.output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    [self.output setMetadataObjectsDelegate:self queue:self.serialQueue];
}

- (void)_configureDevice
{
    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
        [self.device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
        [self.device setSmoothAutoFocusEnabled:NO];
        [self.device unlockForConfiguration];
    } else {
        LXLog(@"%@", error);
    }
}

#pragma mark - 通知

- (void)_registerSessionRunningNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleCaptureSessionNotification:)
                                                 name:AVCaptureSessionRuntimeErrorNotification
                                               object:self.session];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleCaptureSessionNotification:)
                                                 name:AVCaptureSessionDidStartRunningNotification
                                               object:self.session];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleCaptureSessionNotification:)
                                                 name:AVCaptureSessionDidStopRunningNotification
                                               object:self.session];
}

- (void)_handleCaptureSessionNotification:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([notification.name isEqualToString:AVCaptureSessionDidStartRunningNotification]) {
            !self.didStartRunningCallback ?: self.didStartRunningCallback();
            self.didStartRunningCallback = nil;
        }
        else if ([notification.name isEqualToString:AVCaptureSessionDidStopRunningNotification]) {
            !self.didStopRunningCallback ?: self.didStopRunningCallback();
            self.didStopRunningCallback = nil;
        }
        else if ([notification.name isEqualToString:AVCaptureSessionRuntimeErrorNotification]) {
            !self.failureBlock ?: self.failureBlock(notification.userInfo[AVCaptureSessionErrorKey]);
        }
    });
}

#pragma mark - <AVCaptureMetadataOutputObjectsDelegate>

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    NSArray<AVMetadataMachineReadableCodeObject *> *QRCodeObjects = metadataObjects;
    if (metadataObjects.count == 0) {
        return;
    }
    NSArray *messages = [QRCodeObjects valueForKey:@"stringValue"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        !self.completionBlock ?: self.completionBlock(self, messages);
    });
}

@end
