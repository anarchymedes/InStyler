# InStyler
## An iOS 17+ app that lets the user take stylised pictures and capture stylised videos

This app showcases the Core ML Style Transfer capability by allowing the user to choose a style, and then capture photos or record videos stylised accordingly. The captured images and the recorded videos are saved in the user's photo library.
Additionally, the app allows the user to select an existing image or video from their photo library and create a stylised copy of it.

Technically, each style consists of two models: one is trained for images (higher resolution, lower speed, ModelAlgorithmType set to .cnn), and the other, for videos (higher speed, lower resolution and level of details, ModelAlgorithmType set to .cnnLite). Some of the models have been trained using the Create ML app; others, using a dedicated Swift palyground based on [this](https://developer.apple.com/videos/play/wwdc2020/10156) approach. Naturally, each style also includes an image that appears on its card in the UI, the description text, and the colour gradient for the card's background: look into the asset catalogue for more details.

Of course, anyone who gets this repo are welcome, and encouraged, to add their own syles, models and all, or replace the supplied ones with their own. This is one of the reasons this app is _not_ distributed through Apple Store: setting up a public repo for contributed styles would have been a major enterprise of its own. The other reason is that the sylised video capture in particular may be a bit too error-prone to pass the ruthless Apple Store review, especially on older and slower devices. The app handles such errors as gracefully as possible, by showing an elegant view in the UI and allowing the user to continue or try again as they choose (which, I assure you, sometimes works). Even so, this is not the quality Apple apparently demand from anything they allow into the house. Which brings me to the next topic.

### Known Issues and Areas of Improvement

The latest book I found on AVFoundation dated from __2015__. There are _lots_ of tutorials out there, but they all show the basic, most simplistic use case: take a picture, or capture a video (usualy, without the sound). If you would like to _do something_ to every frame of the video before it gets saved (exactly what this app is doing), you're reduced to _trial and error_, made harder by the fact that AVFoundation is an _ancient_ framework that does not work well with Swift, let alone the _brutal_ concurrency enforcement by __Swift 6__, which this code is written in.

My intuition tells me that there _must_ be a way to capture every frame, and then process and record it on a different thread, while also preserving the soundtrack: if the file writing finishes later than the actual capture, so be it, no harm done. And yet, I have not been able to find any guide on how to accomplish this.

On the same note, the app currently builds with _two warnings_, and both are about _isHighResolutionCaptureEnabled_ being deprectaed, and that _maxPhotoDimensions_ should be used instead. However, when I tried this - simply set the dimensions without raising the flag – the app would just _crash_ at runtime. There was _not a single code sample anywhere_ to show how eaxtly the deprecated flag should be replaced by the new size setting. I left the code commented out: if someone figures that one out, I would very much appreciate it if they showed me this trick – and even more so if Apple themselves considered sharing the specific, consise way to replace something they deprecate, rather than a general statement like 'use _that_ instead.'

### Happy coding!
