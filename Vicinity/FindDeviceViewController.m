//
//  FindDeviceViewController.m
//  Vicinity
//
//  Created by Ben Ford on 10/28/13.
//  
//  The MIT License (MIT)
// 
//  Copyright (c) 2013 Instrument Marketing Inc
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#import "FindDeviceViewController.h"
#import "INBeaconService.h"
#import "EasyLayout.h"
#import "ButtonMaker.h"
#import "BeaconCircleView.h"
#import "GraphView.h"

#define USE_RSSI_RANGE NO

#define IS_BEACON NO

#define GRAPH_UPDATE_INTERVAL 5

#define Delay_INDetectorRangeImmediate	1.2f
#define Delay_INDetectorRangeNear		1.5f
#define Delay_INDetectorRangeFar		1.8f

#define ColorFirst	[UIColor greenColor]
#define ColorSecond [UIColor yellowColor]
#define ColorThird	[UIColor orangeColor]
#define ColorFourth [UIColor redColor]

#define ColorChangeInterval 5.0f

@interface FindDeviceViewController () <INBeaconServiceDelegate>

@end

@implementation FindDeviceViewController
{
	GraphView *graph;
    UILabel *statusLabel;
    UILabel *delayLabel;
	UILabel *rssiLabel;
	NSMutableArray *rssiValues;
    BeaconCircleView *baseCircle;
    BeaconCircleView *targetCircle;
    UIButton *modeButton;
	bool colorChangeEnabled;
	bool graphViewEnabled;
	int graphUpdateCount;
}

#pragma mark - View Lifecycle

- (id)init
{
    if ((self = [super init])) {

    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	[self loadUI];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
	if(IS_BEACON){
		[self startBroadCasting];
	} else {
		[self startDetecting];
	}
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	if(IS_BEACON){
		[self stopBroadCasting];
	} else {
		[self stopDetecting];
	}
}

#pragma mark - INBeaconServiceDelegate

/*
 * Method called by the iBeacon, starts the animation
 * @param uuid string the unique device identifier
 * @param range INDetectorRange the detected range between the iBeacon and the device
 * @param delay float the calculated delay based on the detected RSSI value
 * @param rssi int the detected RSSI value
 * @param date NSDate the date and time the iBeacon sent the message to this device
 */
- (void)service:(INBeaconService *)service foundDeviceUUID:(NSString *)uuid withRange:(INDetectorRange)range andDelay:(float)delay andRSSI:(int)rssi andDate:(NSDate *)date
{
	if(range != INDetectorRangeUnknown){
		if(USE_RSSI_RANGE){
			[self startAnimationWithTime:[self calculateTimeLeft:date] andRange:range];
		} else {
			[self startAnimationWithTime:[self calculateTimeLeft:date] andDelay:delay];
		}
	} else {
		[self.view setBackgroundColor:[UIColor whiteColor]];
	}
	
	[rssiLabel setText:[NSString stringWithFormat:@"RSSI: %i", rssi]];
	[delayLabel setText:[NSString stringWithFormat:@"Delay: %.2f", delay]];
	[rssiValues addObject:[NSNumber numberWithDouble:rssi * -0.01]];
	
	if(graphViewEnabled){
		[self updateGraph];
	}
}

#pragma mark - Graph Methods

/*
 * Method to update graph at the defined interval
 */
- (void)updateGraph
{
	graphUpdateCount ++;
	if(graphUpdateCount >= GRAPH_UPDATE_INTERVAL){
		[graph updateGraph];
		graphUpdateCount = 0;
	}
}

#pragma mark - Animation Methods

/*
 * Method to start Animation based on a delay
 * @param time NSTimeInterval the ColorChangeInterval minus the time it took to send the message from the iBeacon to the device
 * @param delay float the calculated delay based on the detected RSSI value
 */
- (void)startAnimationWithTime:(NSTimeInterval)time andDelay:(float)delay
{
	if(colorChangeEnabled){
		colorChangeEnabled = false;
		[self performSelector:@selector(setBackgroundColor) withObject:nil afterDelay:delay];
		[self performSelector:@selector(enableColorChange) withObject:nil afterDelay:time];
	}
}

/*
 * Method to start Animation based on a delay
 * @param time NSTimeInterval the ColorChangeInterval minus the time it took to send the message from the iBeacon to the device
 * @param range INDetectorRange the determined range
 */
- (void)startAnimationWithTime:(NSTimeInterval)time andRange:(INDetectorRange)range
{
	if(colorChangeEnabled){
		colorChangeEnabled = false;
		switch (range) {
			case INDetectorRangeImmediate:
				[self performSelector:@selector(setBackgroundColor) withObject:nil afterDelay:Delay_INDetectorRangeImmediate];
				[self performSelector:@selector(enableColorChange) withObject:nil afterDelay:time];
				break;
			case INDetectorRangeNear:
				[self performSelector:@selector(setBackgroundColor) withObject:nil afterDelay:Delay_INDetectorRangeNear];
				[self performSelector:@selector(enableColorChange) withObject:nil afterDelay:time];
				break;
			case INDetectorRangeFar:
				[self performSelector:@selector(setBackgroundColor) withObject:nil afterDelay:Delay_INDetectorRangeFar];
				[self performSelector:@selector(enableColorChange) withObject:nil afterDelay:time];
				break;
			default:
				break;
		}
	}
}

/*
 * Method to enable listening for the next color change
 */
- (void)enableColorChange
{
	colorChangeEnabled = true;
}

/*
 * Method to set a background color based on the last background color
 */
- (void)setBackgroundColor
{
	if(self.view.backgroundColor == ColorFirst){
		[self.view setBackgroundColor:ColorSecond];
	} else if(self.view.backgroundColor == ColorSecond){
		[self.view setBackgroundColor:ColorThird];
	} else if(self.view.backgroundColor == ColorThird){
		[self.view setBackgroundColor:ColorFourth];
	} else {
		[self.view setBackgroundColor:ColorFirst];
	}
}

/*
 * Method to calculate the delay between the time the iBeacon sent the message 
 * and the time the device received the message
 * @param NSDate date the date and time the iBeacon sent the message
 * @returns NSTimeInterval time the ColorChangeInterval minus the time 
 * it took for the device to receive the message from the iBeacon
 */
- (NSTimeInterval)calculateTimeLeft:(NSDate *)date
{
	NSTimeInterval operationTime = ColorChangeInterval;
	NSTimeInterval timeInterval = [date timeIntervalSinceNow];
	return (operationTime + timeInterval);
}

#pragma mark - State Methods

/* 
 * Method to start detecting iBeacons
 */
- (void)startDetecting
{
	if(![[INBeaconService singleton] isDetecting]){
		[[INBeaconService singleton] addDelegate:self];
		[[INBeaconService singleton] startDetecting];
		[self changeInterfaceToDetectMode];
	}
}
/*
 * Method to stop detecting iBeacons
 */
- (void)stopDetecting
{
	if([[INBeaconService singleton] isDetecting]){
		[[INBeaconService singleton] removeDelegate:self];
		[[INBeaconService singleton] stopDetecting];
		[self changeInterfaceToOffMode];
	}
}
/*
 * Method to start detecting broadcasting to devices
 */
- (void)startBroadCasting
{
	if(![[INBeaconService singleton] isBroadcasting]){
		[[INBeaconService singleton] addDelegate:self];
		[[INBeaconService singleton] startBroadcasting];
		[self changeInterfaceToBroadcastMode];
	}
}
/*
 * Method to stop detecting broadcasting to devices
 */
- (void)stopBroadCasting
{
	if([[INBeaconService singleton] isBroadcasting]){
		[[INBeaconService singleton] removeDelegate:self];
		[[INBeaconService singleton] stopBroadcasting];
		[self changeInterfaceToOffMode];
	}
}

#pragma mark - Button Action

/*
 * Method to change the state
 */
- (void)didToggleMode:(UIButton *)button
{
	if(IS_BEACON){
		if([button isSelected]) {
			[self stopBroadCasting];
		} else {
			[self startBroadCasting];
		}
	} else {
		if ([button isSelected]) {
			[self stopDetecting];
		} else {
			[self startDetecting];
		}
	}
}

#pragma mark - UI Methods

/*
 * Method to load the initial UI
 */
- (void)loadUI
{
	self.view.backgroundColor = [UIColor whiteColor];
    
    UIView *bottomToolbar = [[UIView alloc] init];
    [bottomToolbar setBackgroundColor:[UIColor colorWithWhite:0.11f alpha:1.0f]];
    [bottomToolbar setExtSize:CGSizeMake(self.view.extSize.width, 82.0f)];
    [EasyLayout bottomCenterView:bottomToolbar inParentView:self.view offset:CGSizeZero];
    [self.view addSubview:bottomToolbar];
    
    statusLabel = [[UILabel alloc] init];
    [statusLabel setTextColor:[UIColor whiteColor]];
    [statusLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:28.0f]];
    [statusLabel setText:@"Searching..."];
	[statusLabel setBackgroundColor:[UIColor clearColor]];
    [EasyLayout sizeLabel:statusLabel mode:ELLineModeSingle maxWidth:self.view.extSize.width];
    [EasyLayout centerView:statusLabel inParentView:bottomToolbar offset:CGSizeZero];
    [bottomToolbar addSubview:statusLabel];
    
    baseCircle = [[BeaconCircleView alloc] init];
    [EasyLayout positionView:baseCircle aboveView:bottomToolbar horizontallyCenterWithView:self.view offset:CGSizeMake(0.0f, -50.0f)];
    [self.view addSubview:baseCircle];
    
    targetCircle = [[BeaconCircleView alloc] init];
    [EasyLayout topCenterView:targetCircle inParentView:self.view offset:CGSizeMake(0.0f, 50.0f)];
    [self.view addSubview:targetCircle];
    
    delayLabel = [[UILabel alloc] init];
	[delayLabel setTextColor:[UIColor blackColor]];
    [delayLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:16.0f]];
	[delayLabel setText:@"Delay: 0.00"];
	[delayLabel setBackgroundColor:[UIColor clearColor]];
    [EasyLayout sizeLabel:delayLabel mode:ELLineModeMulti maxWidth:100.0f];
    [EasyLayout positionView:delayLabel toRightAndVerticalCenterOfView:targetCircle offset:CGSizeMake(15.0f, 0.0f)];
    [self.view addSubview:delayLabel];
	
	rssiLabel = [[UILabel alloc] init];
    [rssiLabel setTextColor:[UIColor blackColor]];
    [rssiLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:16.0f]];
    [rssiLabel setText:@"RSSI: -00"];
	[rssiLabel setBackgroundColor:[UIColor clearColor]];
    [EasyLayout sizeLabel:rssiLabel mode:ELLineModeMulti maxWidth:100.0f];
    [EasyLayout positionView:rssiLabel toRightAndVerticalCenterOfView:targetCircle offset:CGSizeMake(15.0f, 30.0f)];
    [self.view addSubview:rssiLabel];
	
	if(IS_BEACON){
		modeButton = [ButtonMaker plainButtonWithNormalImageName:@"mode_button_broadcasting_off.png" selectedImageName:@"mode_button_broadcasting.png"];
	} else {
		modeButton = [ButtonMaker plainButtonWithNormalImageName:@"mode_button_detecting_off.png" selectedImageName:@"mode_button_detecting.png"];
	}
    [modeButton addTarget:self action:@selector(didToggleMode:) forControlEvents:UIControlEventTouchUpInside];
	[modeButton setSelected:TRUE];
    [EasyLayout positionView:modeButton aboveView:bottomToolbar offset:CGSizeMake(10.0f, -10.0f)];
	[self.view addSubview:modeButton];
	
	if(!IS_BEACON){
		rssiValues = [[NSMutableArray alloc]init];
		CGRect rect = CGRectMake(0.0f, 0.0f, self.view.frame.size.width, self.view.frame.size.height - 82.0f);
		graph = [[GraphView alloc]initWithFrame:rect];
		[graph setDefaultArray:rssiValues];
		[self.view addSubview:graph];
		[self.view bringSubviewToFront:modeButton];
		graphViewEnabled = true;
		graphUpdateCount = 0;
	}
}

/*
 * Method to load the broadcast UI
 */
- (void)changeInterfaceToBroadcastMode
{
	[statusLabel setText:@"Broadcasting..."];
    [EasyLayout sizeLabel:statusLabel mode:ELLineModeSingle maxWidth:self.view.extSize.width];
    [targetCircle setHidden:true];
    [delayLabel setHidden:true];
	[rssiLabel setHidden:true];
	[modeButton setSelected:true];
    [baseCircle startAnimationWithDirection:BeaconDirectionUp];
}

/*
 * Method to load the detect UI
 */
- (void)changeInterfaceToDetectMode
{
    [statusLabel setText:@"Detecting..."];
    [EasyLayout sizeLabel:statusLabel mode:ELLineModeSingle maxWidth:self.view.extSize.width];
	[targetCircle setHidden:false];
    [delayLabel setHidden:false];
	[rssiLabel setHidden:false];
	[modeButton setSelected:true];
    [targetCircle startAnimationWithDirection:BeaconDirectionDown];
	colorChangeEnabled = true;
	[graph setDefaultArray:rssiValues];
}

/*
 * Method to load the stopped UI
 */
- (void)changeInterfaceToOffMode
{
	[statusLabel setText:@"Stopped..."];
	[targetCircle setHidden:true];
	[delayLabel setHidden:true];
	[rssiLabel setHidden:true];
	[modeButton setSelected:false];
	
	if(IS_BEACON){
		[baseCircle stopAnimation];
	} else {
		rssiValues = [[NSMutableArray alloc]init];
		[targetCircle stopAnimation];
	}
}

#pragma mark - Supported Orientations

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

@end
