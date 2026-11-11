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

static NSDictionary *AudioToggleRoute(NSString *routeId, NSString *type, NSString *name, BOOL selected) {
	return @{@"id": routeId, @"type": type, @"name": name ?: @"", @"selected": @(selected)};
}

static BOOL AudioToggleIsWiredPort(NSString *portType) {
	return [portType isEqualToString:AVAudioSessionPortHeadsetMic]
		|| [portType isEqualToString:AVAudioSessionPortHeadphones]
		|| [portType isEqualToString:AVAudioSessionPortUSBAudio];
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

- (NSArray<NSDictionary *> *) audioRoutes {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	AVAudioSessionPortDescription *output = session.currentRoute.outputs.firstObject;
	NSString *outputType = output.portType;
	BOOL outputIsBluetooth = [outputType isEqualToString:AVAudioSessionPortBluetoothHFP];

	AVAudioSessionPortDescription *wiredPort = AudioToggleIsWiredPort(outputType) ? output : nil;
	for (AVAudioSessionPortDescription *input in session.availableInputs) {
		if (!wiredPort && AudioToggleIsWiredPort(input.portType)) {
			wiredPort = input;
		}
	}

	NSMutableArray<NSDictionary *> *routes = [NSMutableArray array];
	BOOL hasReceiver = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone;
	if (wiredPort) {
		[routes addObject:AudioToggleRoute(@"wired", @"wired", wiredPort.portName, AudioToggleIsWiredPort(outputType))];
	} else if (hasReceiver) {
		[routes addObject:AudioToggleRoute(@"earpiece", @"earpiece", @"", [outputType isEqualToString:AVAudioSessionPortBuiltInReceiver])];
	}
	for (AVAudioSessionPortDescription *input in session.availableInputs) {
		if ([input.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
			BOOL selected = outputIsBluetooth
				&& ([input.UID isEqualToString:output.UID] || [input.portName isEqualToString:output.portName]);
			[routes addObject:AudioToggleRoute(input.UID, @"bluetooth", input.portName, selected)];
		}
	}
	[routes addObject:AudioToggleRoute(@"speaker", @"speaker", @"", [outputType isEqualToString:AVAudioSessionPortBuiltInSpeaker])];
	return routes;
}

- (AVAudioSessionPortDescription *) inputForRoute:(NSString *)routeId {
	for (AVAudioSessionPortDescription *input in [AVAudioSession sharedInstance].availableInputs) {
		if (([routeId isEqualToString:@"earpiece"] && [input.portType isEqualToString:AVAudioSessionPortBuiltInMic])
			|| ([routeId isEqualToString:@"wired"] && AudioToggleIsWiredPort(input.portType))
			|| [routeId isEqualToString:input.UID]) {
			return input;
		}
	}
	return nil;
}

- (void) getAudioRoutes:(CDVInvokedUrlCommand *)command {
	[self.commandDelegate runInBackground:^{
		CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:[self audioRoutes]];
		[self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
	}];
}

/* Only the output override and the preferred input change here. The session
 * category belongs to Twilio (voice) and iosrtc (video). */
- (void) setAudioRoute:(CDVInvokedUrlCommand *)command {
	NSString *routeId = [NSString stringWithFormat:@"%@", command.arguments.firstObject];
	[self.commandDelegate runInBackground:^{
		NSError *err = nil;
		AVAudioSession *session = [AVAudioSession sharedInstance];
		BOOL ok;
		if ([routeId isEqualToString:@"speaker"]) {
			ok = [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];
		} else {
			AVAudioSessionPortDescription *input = [self inputForRoute:routeId];
			BOOL headphonesWithoutMic = !input && [routeId isEqualToString:@"wired"];
			ok = (input || headphonesWithoutMic)
				&& [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&err]
				&& [session setPreferredInput:input error:&err];
		}
		[self logRoute:[NSString stringWithFormat:@"setAudioRoute %@%@%@", routeId, ok ? @"" : @" failed",
			err ? [NSString stringWithFormat:@" error=%@", err.localizedDescription] : @""]];
		CDVPluginResult *result = ok
			? [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
			: [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Unknown audio route %@", routeId]];
		[self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
	}];
}

- (void) sendRoutes {
	NSString *callbackId = [self callbackIdForEvent:@"routes"];
	if (!callbackId) {
		return;
	}
	CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:[self audioRoutes]];
	[result setKeepCallbackAsBool:YES];
	[self.commandDelegate sendPluginResult:result callbackId:callbackId];
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
	[self sendRoutes];
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
