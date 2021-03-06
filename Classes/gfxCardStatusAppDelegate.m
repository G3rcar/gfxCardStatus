//
//  gfxCardStatusAppDelegate.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 4/22/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import "gfxCardStatusAppDelegate.h"
#import "NSAttributedString+Hyperlink.h"
#import "GeneralPreferencesViewController.h"
#import "AdvancedPreferencesViewController.h"
#import "GSProcess.h"
#import "GSMux.h"
#import "GSNotifier.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

#define kHasSeenOneTimeNotificationKey @"hasSeenVersionTwoMessage"

@implementation gfxCardStatusAppDelegate

@synthesize menuController;

#pragma mark - Initialization

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    GTMLogger *logger = [GTMLogger sharedLogger];
    [logger setFilter:[[GTMLogNoFilter alloc] init]];

    // Initialize the preferences object and set default preferences if this is
    // a first-time run.
    _prefs = [GSPreferences sharedInstance];

    // Attempt to open a connection to AppleGraphicsControl.
    if (![GSMux switcherOpen]) {
        GTMLoggerError(@"Can't open connection to AppleGraphicsControl. This probably isn't a gfxCardStatus-compatible machine.");
        
        [GSNotifier showUnsupportedMachineMessage];
        [menuController quit:self];
    } else {
        GTMLoggerInfo(@"GPUs present: %@", [GSGPU getGPUNames]);
        GTMLoggerInfo(@"Integrated GPU name: %@", [GSGPU integratedGPUName]);
        GTMLoggerInfo(@"Discrete GPU name: %@", [GSGPU discreteGPUName]);

        if (![GSGPU isLegacyMachine])
        {
            // If there is no external display, switch to integrated only, otherwise, use dynamic
            if ([self hasExternalDisplay])
            {
                [menuController setMode:menuController.dynamicSwitching];
            } else
            {
                [menuController setMode:menuController.integratedOnly];
            }
        }
    }

    // Now accepting GPU change notifications! Apply at your nearest GSGPU today.
    [GSGPU registerForGPUChangeNotifications:self];

    // Register with NSWorkspace for system shutdown notifications to ensure
    // proper termination in the event of system shutdown and/or user logout.
    // Goal is to ensure machine is set to default dynamic switching before shut down.
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    [[workspace notificationCenter] addObserver:self
                                       selector:@selector(workspaceWillPowerOff:)
                                           name:NSWorkspaceWillPowerOffNotification
                                         object:workspace];

    // Initialize the menu bar icon and hook the menu up to it.
    [menuController setupMenu];

    // Show the one-time startup notification asking users to be kind and donate
    // if they like gfxCardStatus. Then make it go away forever.
    if (![_prefs boolForKey:kHasSeenOneTimeNotificationKey]) {
        [GSNotifier showOneTimeNotification];
        [_prefs setBool:YES forKey:kHasSeenOneTimeNotificationKey];
    }

    // If we're not on 10.8+, fall back to Growl for notifications.
    if (![GSNotifier notificationCenterIsAvailable])
        [GrowlApplicationBridge setGrowlDelegate:[GSNotifier sharedInstance]];
}

- (boolean_t)hasExternalDisplay
{
    // Determine if there are external displays connected
    CGDirectDisplayID displays[2];
    uint32_t numberOfDisplays;
    
    if (CGGetActiveDisplayList (2, displays, &numberOfDisplays ) == 0)
    {
        
        if (numberOfDisplays > 1 || (numberOfDisplays == 1 && !CGDisplayIsBuiltin(displays[0])))
        {
            return true;
        }
    }
    
    return false;
}

#pragma mark - Termination Notifications

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Set the machine to dynamic switching before shutdown to avoid machine restarting
    // stuck in a forced GPU mode.
    if (![GSGPU isLegacyMachine]) {
        [GSMux setMode:GSSwitcherModeDynamicSwitching];
    }

    GTMLoggerDebug(@"Termination notification received. Going to Dynamic Switching.");
}

- (void)workspaceWillPowerOff:(NSNotification *)aNotification
{
    // Selector called in response to application termination notification from
    // NSWorkspace. Also implemented to avoid the machine shuting down in a forced
    // GPU state.
    [[NSApplication sharedApplication] terminate:self];
    GTMLoggerDebug(@"NSWorkspaceWillPowerOff notification received. Terminating application.");
}

#pragma mark - GSGPUDelegate protocol

- (void)GPUDidChangeTo:(GSGPUType)gpu
{
    /*int savedMode = self.savedMode;
    if (((savedMode == MODE_INTEGRATED_ONLY) && (gpu != GSGPUTypeIntegrated)) ||
        ((savedMode == MODE_DISCRETE_ONLY) && (gpu != GSGPUTypeDiscrete))) {
        GTMLoggerDebug(@"GPU changed to something that I don't want, attempting reset...");
        [self setModeToSavedMode];
    }*/
    [menuController updateMenu];
    [GSNotifier showGPUChangeNotification:gpu];
}

@end
