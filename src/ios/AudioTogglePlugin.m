#import "AudioTogglePlugin.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const SpeakerSelectedNotification = @"speaker";
NSString *const AudioOptionsAvailable = @"audioOutputsAvailable";

static NSString *AudioToggleReasonName(AVAudioSessionRouteChangeReason reason) {
	switch (reason) {
		case AVAudioSessionRouteChangeReasonNewDeviceAvailable: return @"newDeviceAvailable";
		case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: return @"oldDeviceUnavailable";
		case AVAudioSessionRouteChangeReasonCategoryChange: return @"categoryChange";
		case AVAudioSessionRouteChangeReasonOverride: return @"override";
		case AVAudioSessionRouteChangeReasonWakeFromSleep: return @"wakeFromSleep";
		case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory: return @"noSuitableRouteForCategory";
		case AVAudioSessionRouteChangeReasonRouteConfigurationChange: return @"routeConfigurationChange";
		default: return [NSString stringWithFormat:@"%lu", (unsigned long)reason];
	}
}

static NSString *AudioTogglePorts(NSArray<AVAudioSessionPortDescription *> *ports) {
	NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:ports.count];
	for (AVAudioSessionPortDescription *port in ports) {
		[names addObject:[NSString stringWithFormat:@"%@:%@", port.portType, port.portName]];
	}
	return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

@interface AudioTogglePlugin()
@property (nonatomic, strong) NSMutableDictionary *eventCallbacks;
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic) BOOL audioOutputsAvailable;
@end

@implementation AudioTogglePlugin

- (void) pluginInitialize {
	self.eventCallbacks = [NSMutableDictionary dictionaryWithCapacity:2];

	self.audioOutputsAvailable = false;
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (NSString *)callbackIdForEvent:(NSString *)eventName {
	id callbackId = self.eventCallbacks[eventName];
	if (![callbackId isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSString *callbackIdString = (NSString *)callbackId;
	return callbackIdString.length > 0 ? callbackIdString : nil;
}


- (void) audioRoutingOptionsChangeDetector:(BOOL) newValue {
	if	(newValue != self.audioOutputsAvailable) {
		self.audioOutputsAvailable = newValue;
		NSString *callbackId = [self callbackIdForEvent:@"audioOutputsAvailable"];
		if (!callbackId) {
			return;
		}
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:self.audioOutputsAvailable];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    
	}
}

- (BOOL) checkAudioRoutingOptions:(CDVInvokedUrlCommand *)command {
	NSArray<AVAudioSessionPortDescription *> *inputs = [AVAudioSession sharedInstance].availableInputs;
	
	BOOL hasOptions = inputs.count > 1;
	[self audioRoutingOptionsChangeDetector: hasOptions];
	if (!command) {
		return hasOptions;
	}
	
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:hasOptions];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
	
	return hasOptions;
}
- (BOOL) isSpeakerphoneOn:(CDVInvokedUrlCommand *)command {
    BOOL isSpeakerPhoneOn = false;
    AVAudioSessionRouteDescription *currentRoute = [AVAudioSession sharedInstance].currentRoute;
    if(currentRoute != nil){
        if(currentRoute.outputs.count > 0){
            AVAudioSessionPortDescription *output = currentRoute.outputs.firstObject;
            if(output != nil){
                isSpeakerPhoneOn = [output.portType isEqual: @"Speaker"];
            }
        }
    }
    CDVPluginResult* pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:isSpeakerPhoneOn];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    return isSpeakerPhoneOn;
}


- (void)setAudioMode:(CDVInvokedUrlCommand *)command
{
	NSError* __autoreleasing err = nil;
	NSString* mode = [[NSString stringWithFormat:@"%@", [command.arguments objectAtIndex:0]] lowercaseString];

	AVAudioSession *session = [AVAudioSession sharedInstance];

	if ([mode isEqualToString:@"earpiece"]) {
		[session setCategory:AVAudioSessionCategoryPlayAndRecord error:&err];
		[session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&err];

	} else if ([mode isEqualToString:@"speaker"] || [mode isEqualToString:@"ringtone"]) {
		[session setCategory:AVAudioSessionCategoryPlayAndRecord error:&err];
		[session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];

	} else if ([mode isEqualToString:@"normal"]) {
		[session setCategory:AVAudioSessionCategorySoloAmbient error:&err];
	}

	[self logRoute:[NSString stringWithFormat:@"setAudioMode %@%@", mode,
		err ? [NSString stringWithFormat:@" error=%@", err.localizedDescription] : @""]];
}

- (void) logRoute:(NSString *)why {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	AVAudioSessionRouteDescription *route = session.currentRoute;
	NSLog(@"[AudioToggle] %@: out=%@ in=%@ available=%@ category=%@ options=0x%lx mode=%@",
		why, AudioTogglePorts(route.outputs), AudioTogglePorts(route.inputs),
		AudioTogglePorts(session.availableInputs), session.category,
		(unsigned long)session.categoryOptions, session.mode);
}

-(void) displayIOSAudioRoutingComponent:(CDVInvokedUrlCommand *)command {
	if (!self.volumeView) {
		self.volumeView = [MPVolumeView new];
		self.volumeView.showsRouteButton = YES;
		self.volumeView.showsVolumeSlider = NO;
		self.volumeView.hidden = true;
		UIViewController *rootController = [UIApplication sharedApplication].delegate.window.rootViewController;
		[rootController.view addSubview:self.volumeView];
	}
	for (UIButton *button in self.volumeView.subviews)
	{
		if ([button isKindOfClass:[UIButton class]])
		{
			[button sendActionsForControlEvents:UIControlEventTouchUpInside];
			return;
		}
	}
}

- (void) registerListener:(CDVInvokedUrlCommand *)command {
	NSString* eventName = command.arguments.firstObject;
	//if(self.eventCallbacks[eventName] != nil) {
    [self.eventCallbacks setValue:command.callbackId forKey:eventName];

	//}
	[self logRoute:[NSString stringWithFormat:@"listener %@", eventName]];
}

- (void)handleAudioRouteChange:(NSNotification *) notification
{
	[self checkAudioRoutingOptions:nil];
	AVAudioSessionRouteChangeReason reasonValue = [notification.userInfo[@"AVAudioSessionRouteChangeReasonKey"] unsignedIntegerValue];
	AVAudioSessionRouteDescription *previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
	[self logRoute:[NSString stringWithFormat:@"route change %@ (was out=%@ in=%@)", AudioToggleReasonName(reasonValue),
		AudioTogglePorts(previousRoute.outputs), AudioTogglePorts(previousRoute.inputs)]];
	AVAudioSessionRouteDescription* currentRoute = [AVAudioSession sharedInstance].currentRoute;
	if([currentRoute.outputs count] > 0 && (reasonValue == AVAudioSessionRouteChangeReasonOverride || reasonValue == AVAudioSessionRouteChangeReasonCategoryChange)) {
		AVAudioSessionPortDescription *output = currentRoute.outputs.firstObject;
		NSString *callbackId = [self callbackIdForEvent:@"speaker"];
		if (!callbackId) {
			return;
		}
		
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[output.portType isEqual: @"Speaker"]];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];

	}
}

@end
