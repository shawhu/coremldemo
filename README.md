Hello world.

Prerequisites:

- iOS device with iOS 11 beta or released version
- Xcode 9.0 beta or released version
- high sierra is not required

This uses the AVFoundation to grab the video feed from the camera, pick the Luma plane (black and white), cropped and resized to 224x224x8 using Accelerate/vImage (required by Resnet50 mlmodel) and finally processed in another thread using dispatch_async

All the codes are kept in the main viewcontroller ViewController.m

Results:

Screenshots
<p align="left">
  <img src="https://raw.githubusercontent.com/shawhu/coremldemo/master/screenshots/IMG_0259.PNG" width="350"/>
</p>
