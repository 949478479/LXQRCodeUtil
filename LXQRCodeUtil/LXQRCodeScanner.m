//
//  LXQRCodeScanner.m
//  LXQRCodeUtil_demo
//
//  Created by 从今以后 on 2017/5/25.
//  Copyright © 2017年 从今以后. All rights reserved.
//

#import "LXQRCodeScanner.h"

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

@property (nonatomic) void (^startRunningCompletion)(BOOL, NSError *);
@property (nonatomic) void (^stopRunningCompletion)(void);

@end

@implementation LXQRCodeScanner
@synthesize previewView = _previewView;

- (void)dealloc {
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

- (void)startRunningWithCompletion:(void (^)(BOOL, NSError * _Nullable))completion
{
    if (self.session.isRunning) {
        return;
    }
    
    self.startRunningCompletion = completion;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                dispatch_async(self.serialQueue, ^{
					if (self.session.isRunning) {
						return;
					}
                    if ([self _addDeviceInput]) {
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
				!self.startRunningCompletion ?: self.startRunningCompletion(NO, error);
            }
        });
    }];
}

- (void)stopRunningWithCompletion:(void (^)(void))completion
{
    if (self.session.isRunning) {
		_stopRunningCompletion = completion;
		dispatch_async(self.serialQueue, ^{
			[self.session stopRunning];
		});
    }
}

#pragma mark - 手电筒

- (void)setTorchActive:(BOOL)torchActive
{
	_torchActive = torchActive;

	NSError *error = nil;
	if ([self.device lockForConfiguration:&error]) {
		self.device.torchMode = torchActive ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
		[self.device unlockForConfiguration];
	} else {
		!self.failureBlock ?: self.failureBlock(error);
	}
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

	!self.startRunningCompletion ?: self.startRunningCompletion(NO, error);

    return NO;
}

- (void)_addMetadataOutput
{
    if (!self.output) {
		self.output = [AVCaptureMetadataOutput new];
		[self.session addOutput:self.output];
		self.output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
		[self.output setMetadataObjectsDelegate:self queue:self.serialQueue];
    }
}

- (void)_configureDevice
{
    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
		self.device.smoothAutoFocusEnabled = NO;
		self.device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
		self.device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
        [self.device unlockForConfiguration];
    } else {
		!self.startRunningCompletion ?: self.startRunningCompletion(NO, error);
    }
}

#pragma mark - 通知

- (void)_registerSessionRunningNotification
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	[center addObserver:self
			   selector:@selector(_handleCaptureSessionNotification:)
				   name:AVCaptureSessionDidStartRunningNotification
				 object:self.session];
    
	[center addObserver:self
			   selector:@selector(_handleCaptureSessionNotification:)
				   name:AVCaptureSessionDidStopRunningNotification
				 object:self.session];

	[center addObserver:self
			   selector:@selector(_handleCaptureSessionNotification:)
				   name:AVCaptureSessionRuntimeErrorNotification
				 object:self.session];
}

- (void)_handleCaptureSessionNotification:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([notification.name isEqualToString:AVCaptureSessionDidStartRunningNotification]) {
            !self.startRunningCompletion ?: self.startRunningCompletion(YES, nil);
            self.startRunningCompletion = nil;
        }
        else if ([notification.name isEqualToString:AVCaptureSessionDidStopRunningNotification]) {
            !self.stopRunningCompletion ?: self.stopRunningCompletion();
            self.stopRunningCompletion = nil;
        }
        else if ([notification.name isEqualToString:AVCaptureSessionRuntimeErrorNotification]) {
            !self.failureBlock ?: self.failureBlock(notification.userInfo[AVCaptureSessionErrorKey]);
        }
    });
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

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
