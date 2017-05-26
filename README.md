# LXQRCodeUtil

![](https://github.com/949478479/LXQRCodeUtil/blob/screenshot/1.png)
![](https://github.com/949478479/LXQRCodeUtil/blob/screenshot/2.png)

```objective-c
/// 设置窗口区域
self.scanner.rectOfInterest = rectOfInterest;

self.scanner.completionBlock = ^(LXQRCodeScanner *scanner, NSArray<NSString *> *messages) {
    // 处理扫描结果
};

self.scanner.failureBlock = ^(NSError *error) {
    // 处理错误。。。
};

[self.scanner startRunningWithCallback:^{
    // 扫描启动后执行回调
}];
```
