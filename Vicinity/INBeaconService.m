//
//  INBlueToothService.m
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


#import "INBeaconService.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "CLBeacon+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBCentralManager+Ext.h"
#import "CBUUID+Ext.h"

#import "GCDSingleton.h"
#import "ConsoleView.h"
#import "EasedValue.h"

#define DEBUG_CENTRAL		NO
#define DEBUG_PERIPHERAL	NO
#define DEBUG_PROXIMITY		NO

#define UPDATE_INTERVAL 0.3f
#define CBAdvertisementDataLocalNameKey @"iBeacon"

@interface INBeaconService() <CBPeripheralManagerDelegate, CBCentralManagerDelegate>
@end

@implementation INBeaconService
{
    CBUUID *identifier;
    INDetectorRange identifierRange;
	float identifierDelay;
	int RSSIValue;
    CBCentralManager *centralManager;
    CBPeripheralManager *peripheralManager;
    NSMutableSet *delegates;
    EasedValue *easedProximity;
    NSTimer *detectorTimer;
    BOOL bluetoothIsEnabledAndAuthorized;
    NSTimer *authorizationTimer;
}

#pragma mark - Singleton
+ (INBeaconService *)singleton
{
    DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
        return [[self alloc] initWithIdentifier:SINGLETON_IDENTIFIER];
    });
}

#pragma mark - Init

- (id)initWithIdentifier:(NSString *)theIdentifier
{
    if ((self = [super init])) {
        identifier = [CBUUID UUIDWithString:theIdentifier];
        delegates = [[NSMutableSet alloc] init];
        easedProximity = [[EasedValue alloc] init];
        // use to track changes to this value
        bluetoothIsEnabledAndAuthorized = [self hasBluetooth];
        [self startAuthorizationTimer];
    }
    return self;
}

#pragma mark - Delegate Methods

- (void)addDelegate:(id<INBeaconServiceDelegate>)delegate
{
    [delegates addObject:delegate];
}

- (void)removeDelegate:(id<INBeaconServiceDelegate>)delegate
{
    [delegates removeObject:delegate];
}

- (void)performBlockOnDelegates:(void(^)(id<INBeaconServiceDelegate> delegate, float time))block
{
    [self performBlockOnDelegates:block complete:nil];
}

- (void)performBlockOnDelegates:(void(^)(id<INBeaconServiceDelegate> delegate, float time))block complete:( void(^)(void))complete
{
    for (id<INBeaconServiceDelegate>delegate in delegates) {
		float myNotifyTime = ([[delegates allObjects]indexOfObject:delegate]+1) * UPDATE_INTERVAL;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block)
                block(delegate, myNotifyTime);
        });
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (complete)
            complete();
    });
}

- (void)reportRangesToDelegates:(NSTimer *)timer
{
    [self performBlockOnDelegates:^(id<INBeaconServiceDelegate>delegate, float time) {
        [delegate service:self foundDeviceUUID:[identifier representativeString] withRange:identifierRange andDelay:(identifierDelay - time) andRSSI:RSSIValue andDate:[NSDate date]];
    } complete:^{
        // timeout the beacon to unknown position
        // it it's still active it will be updated by central delegate "didDiscoverPeripheral"
        identifierRange = INDetectorRangeUnknown;
    }];
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    if (DEBUG_PERIPHERAL) {
        INLog(@"did discover peripheral: %@, data: %@, %1.2f", [peripheral.identifier UUIDString], advertisementData, [RSSI floatValue]);
        CBUUID *uuid = [advertisementData[CBAdvertisementDataServiceUUIDsKey] firstObject];
        INLog(@"service uuid: %@", [uuid representativeString]);
    }
	
	RSSIValue = [self easedRSSI:[RSSI intValue]];
    identifierDelay = [self convertRSSItoDelay:[RSSI floatValue]];
    identifierRange = [self convertRSSItoINProximity:[RSSI floatValue]];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (DEBUG_CENTRAL)
        INLog(@"-- central state changed: %@", centralManager.stateString);
    if (central.state == CBCentralManagerStatePoweredOn) {
        [self startScanning];
    }
}

#pragma mark - CBPeripheralManagerDelegate

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    if (DEBUG_PERIPHERAL)
        INLog(@"-- peripheral state changed: %@", peripheral.stateString);
    if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
        [self startAdvertising];
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (DEBUG_PERIPHERAL) {
        if (error)
            INLog(@"error starting advertising: %@", [error localizedDescription]);
        else
            INLog(@"did start advertising");
    }
}

#pragma mark - State Methods

- (void)startScanning
{
    NSDictionary *scanOptions = @{CBCentralManagerScanOptionAllowDuplicatesKey:@(YES)};
    [centralManager scanForPeripheralsWithServices:@[identifier] options:scanOptions];
    _isDetecting = YES;
}

- (void)startDetectingBeacons
{
    if (!centralManager)
        centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    detectorTimer = [NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL target:self
                                                   selector:@selector(reportRangesToDelegates:) userInfo:nil repeats:YES];
}

- (void)startBluetoothBroadcast
{
    // start broadcasting if it's stopped
    if (!peripheralManager) {
        peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    }
}

- (void)startAdvertising
{
    NSDictionary *advertisingData = @{CBAdvertisementDataLocalNameKey:CBAdvertisementDataLocalNameKey,
                                      CBAdvertisementDataServiceUUIDsKey:@[identifier]};
    // Start advertising over BLE
    [peripheralManager startAdvertising:advertisingData];
    _isBroadcasting = YES;
}

- (void)startBroadcasting
{
    if (![self canBroadcast])
        return;
    [self startBluetoothBroadcast];
}

- (void)stopBroadcasting
{
    _isBroadcasting = NO;
    // stop advertising beacon data.
    [peripheralManager stopAdvertising];
    peripheralManager = nil;
}

- (void)startDetecting
{
    if (![self canMonitorBeacons])
        return;
    [self startDetectingBeacons];
}

- (void)stopDetecting
{
    _isDetecting = NO;
    [centralManager stopScan];
    centralManager = nil;
    [detectorTimer invalidate];
    detectorTimer = nil;
}

#pragma mark - Bluetooth Auth Methods

- (BOOL)hasBluetooth
{
    return [self canBroadcast] && peripheralManager.state == CBPeripheralManagerStatePoweredOn;
}

- (void)startAuthorizationTimer
{
    authorizationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self
                                                        selector:@selector(checkBluetoothAuth:)
                                                        userInfo:nil repeats:YES];
}
- (void)checkBluetoothAuth:(NSTimer *)timer
{
    if (bluetoothIsEnabledAndAuthorized != [self hasBluetooth]) {
        
        bluetoothIsEnabledAndAuthorized = [self hasBluetooth];
        [self performBlockOnDelegates:^(id<INBeaconServiceDelegate>delegate, float time) {
            if ([delegate respondsToSelector:@selector(service:bluetoothAvailable:)])
                [delegate service:self bluetoothAvailable:bluetoothIsEnabledAndAuthorized];
        }];
    }
}

#pragma mark - RSSI Converstion Methods

/*
 * Method to convert the RSSI value to a delay
 * @param NSInteger proximity the detected RSSI value
 * @returns float the calculated delay
 */
- (float)convertRSSItoDelay:(NSInteger)proximity
{
	easedProximity.value = fabsf(proximity);
    [easedProximity update];
    proximity = easedProximity.value * -1.0f;
	float delay = proximity;
	delay = delay * -0.05f;
	return delay + 1.0f;
}

/*
 * Method to ease the RSSI value
 * @param int proximity the detected RSSI value
 * @returns int the eased RSSI value
 */
- (int)easedRSSI:(int)rssi
{
	easedProximity.value = fabsf(rssi);
    [easedProximity update];
    int easedRSSI = easedProximity.value * -1.0f;
	return easedRSSI;
}

/*
 * Method to convert the RSSI value to INDetectorRange
 * @param NSInteger proximity the detected RSSI value
 * @returns INDetectorRange the determined range
 */
- (INDetectorRange)convertRSSItoINProximity:(NSInteger)proximity
{
    // eased value doesn't support negative values
    easedProximity.value = fabsf(proximity);
    [easedProximity update];
    proximity = easedProximity.value * -1.0f;
    
    if (DEBUG_PROXIMITY)
        INLog(@"proximity: %d", proximity);
    
    
    if (proximity < -70)
        return INDetectorRangeFar;
    if (proximity < -55)
        return INDetectorRangeNear;
    if (proximity < 0)
        return INDetectorRangeImmediate;
    
    return INDetectorRangeUnknown;
}

#pragma mark - Feature Detection Methods

- (BOOL)canBroadcast
{
    // iOS6 can't detect peripheral authorization so just assume it works.
    // ARC complains if we use @selector because `authorizationStatus` is ambiguous
    SEL selector = NSSelectorFromString(@"authorizationStatus");
    if (![[CBPeripheralManager class] respondsToSelector:selector])
        return YES;
    
    CBPeripheralManagerAuthorizationStatus status = [CBPeripheralManager authorizationStatus];
    
    BOOL enabled = (status == CBPeripheralManagerAuthorizationStatusAuthorized ||
                    status == CBPeripheralManagerAuthorizationStatusNotDetermined);
    
    if (!enabled)
        INLog(@"bluetooth not authorized");
    
    return enabled;
}

- (BOOL)canMonitorBeacons
{
    return YES;
}
@end
