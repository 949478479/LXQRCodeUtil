//
//  ViewController.m
//  LXQRCodeUtil_demo
//
//  Created by 从今以后 on 2017/5/25.
//  Copyright © 2017年 从今以后. All rights reserved.
//

#import "ViewController.h"
#import "LXQRCodeScanner.h"
#import "LXQRCodeUtil.h"

@interface ViewController ()
@property (nonatomic) IBOutlet UISwitch *scanSwitch;
@property (nonatomic) IBOutlet UILabel *messageLabel;
@property (nonatomic) IBOutlet LXQRCodeScanner *scanner;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGRect rectOfInterest = {
        40 / width,
        (64 + 40) / height,
        (width - 2 * 40) / width,
        (width - 2 * 40) / height,
    };
    
    __weak typeof(self) weakSelf = self;
    self.scanner.rectOfInterest = rectOfInterest;
    self.scanner.completionBlock = ^(LXQRCodeScanner *scanner, NSArray<NSString *> *messages) {
        weakSelf.messageLabel.text = [messages componentsJoinedByString:@"\n\n"];
    };
    self.scanner.failureBlock = ^(NSError *error) {
        NSLog(@"%@", error);
    };
}

- (IBAction)switchAction:(UISwitch *)sender
{
    if (sender.isOn) {
        [self.scanner startRunningWithCompletion:^(BOOL success, NSError *error){
            self.scanner.previewView.hidden = NO;
        }];
    } else {
        [self.scanner stopRunningWithCompletion:^{
            self.scanner.previewView.hidden = YES;
            self.messageLabel.text = nil;
        }];
    }
}

@end
