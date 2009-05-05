/*

Preferences.m ... Pref Bundle for GriP
 
Copyright (c) 2009, KennyTM~
All rights reserved.
 
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, 
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 * Neither the name of the KennyTM~ nor the names of its contributors may be
   used to endorse or promote products derived from this software without
   specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
*/

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Foundation/Foundation.h>
#import <GriP/Duplex/Client.h>
#import <GriP/common.h>
#import <UIKit/UIKit.h>
#import <GriP/GrowlApplicationBridge.h>
#import <GriP/GPApplicationBridge.h>
#include <notify.h>
#import <GriP/GPGetSmallAppIcon.h>

static GPApplicationBridge* bridge = nil;
static const float perPriorityDefaultSettings[5][9] = {
	{0.400f, 0.400f, 0.400f, 0.75f, 0, 0,  2, 1, 1},
	{0.188f, 0.290f, 0.663f, 0.75f, 1, 0,  2, 2, 2},
	{0.098f, 0.098f, 0.098f, 0.75f, 1, 0,  4, 3, 3},
	{0.349f, 0.024f, 0.016f, 0.80f, 1, 0,  7, 4, 3},
	{0.698f, 0.047f, 0.031f, 0.85f, 1, 0, 10, 4, 3}
};

#define LS(str) [myBundle localizedStringForKey:str value:nil table:nil]

//------------------------------------------------------------------------------
#pragma mark -

extern UIImage* PSSettingsIconImageForUserAppBundlePath(NSString* path);
extern NSString* SBSCopyLocalizedApplicationNameForDisplayIdentifier(NSString* identifier);
extern NSArray* SBSCopyApplicationDisplayIdentifiers(BOOL onlyActive, BOOL unknown);
extern NSString* SBSCopyIconImagePathForDisplayIdentifier(NSString* identifier);
extern void SBBundlePathForDisplayIdentifier(mach_port_t port, const char* identifier, char* result);
extern mach_port_t SBSSpringBoardServerPort();

static inline NSString* GPBundlePathForDisplayIdentifier(mach_port_t port, NSString* identifier) {
	char resstr[1024];
	SBBundlePathForDisplayIdentifier(port, [identifier UTF8String], resstr);
	return [NSString stringWithUTF8String:resstr];
}

@interface UIImage ()
-(UIImage*)_smallApplicationIconImagePrecomposed:(BOOL)precomposed;
@end

static NSComparisonResult comparePSSpecs(PSSpecifier* p1, PSSpecifier* p2, void* context) { return [p1.name localizedCompare:p2.name]; }

//------------------------------------------------------------------------------
#pragma mark -

@interface GPGameModeController : PSListController {
	NSMutableSet* gameModeApps;
}
-(id)initForContentSize:(CGSize)size;
-(void)dealloc;
-(void)suspend;
-(NSArray*)specifiers;
-(void)populateSystemApps;
-(CFBooleanRef)getApp:(PSSpecifier*)spec;
-(void)set:(CFBooleanRef)enable app:(PSSpecifier*)spec;
@end
@implementation GPGameModeController
-(id)initForContentSize:(CGSize)size {
	if ((self = [super initForContentSize:size])) {
		NSArray* gameModeAppsArray = [[NSDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT] objectForKey:@"GameModeApps"] ?: [NSArray array];
		gameModeApps = [[NSMutableSet alloc] initWithArray:gameModeAppsArray];
	}
	return self;
}
-(void)dealloc {
	[gameModeApps release];
	[super dealloc];
}
-(void)suspend {
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT];
	[dict setObject:[gameModeApps allObjects] forKey:@"GameModeApps"];
	[dict writeToFile:GRIP_PREFDICT atomically:NO];
	[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil];
	[super suspend];
}
-(void)populateSystemApps {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	NSMutableArray* systemSpecs = [NSMutableArray array];
	mach_port_t port = SBSSpringBoardServerPort();
	NSArray* sbApps = SBSCopyApplicationDisplayIdentifiers(NO, NO);
	
	for (NSString* identifier in sbApps) {
		NSString* localizedName = SBSCopyLocalizedApplicationNameForDisplayIdentifier(identifier);
		NSString* bundlePath = GPBundlePathForDisplayIdentifier(port, identifier);
		UIImage* image = PSSettingsIconImageForUserAppBundlePath(bundlePath) ?: GPGetSmallAppIcon(identifier);
		if (image == nil) {
			NSString* iconPath = SBSCopyIconImagePathForDisplayIdentifier(identifier);
			image = [[UIImage imageWithContentsOfFile:iconPath] _smallApplicationIconImagePrecomposed:YES];
			[iconPath release];
		}
		PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:localizedName
														   target:self
															  set:@selector(set:app:)
															  get:@selector(getApp:)
														   detail:Nil
															 cell:PSSwitchCell
															 edit:Nil];
		[localizedName release];
		[spec setProperty:image forKey:@"iconImage"];
		[spec setProperty:identifier forKey:@"id"];
		[systemSpecs addObject:spec];
	}
	[sbApps release];
	
	// sort the array using the localized name.
	[systemSpecs sortUsingFunction:&comparePSSpecs context:NULL];
	
	NSInvocation* invoc = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(insertContiguousSpecifiers:atIndex:animated:)]];
	BOOL _yes = YES;
	int index = 1;
	[invoc setTarget:self];
	[invoc setSelector:@selector(insertContiguousSpecifiers:atIndex:animated:)];
	[invoc setArgument:&systemSpecs atIndex:2];
	[invoc setArgument:&index atIndex:3];
	[invoc setArgument:&_yes atIndex:4];
	[invoc retainArguments];
	
	[invoc performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
	[[UIApplication sharedApplication] performSelectorOnMainThread:@selector(setNetworkActivityIndicatorVisible:) withObject:NO waitUntilDone:NO];
	
	[pool drain];
}

-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"Game mode" target:self] retain];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		[self performSelectorInBackground:@selector(populateSystemApps) withObject:nil];
	}
	return _specifiers;
}
-(CFBooleanRef)getApp:(PSSpecifier*)spec { return [gameModeApps containsObject:spec.identifier] ? kCFBooleanTrue : kCFBooleanFalse; }
-(void)set:(CFBooleanRef)enable app:(PSSpecifier*)spec {
	NSString* iden = spec.identifier;
	if (enable == kCFBooleanTrue)
		[gameModeApps addObject:iden];
	else
		[gameModeApps removeObject:iden];
}
@end

//------------------------------------------------------------------------------

@interface GPPerPrioritySettingsController : PSListController {
	NSMutableArray* components;
	int j;
}
-(NSArray*)specifiers;
-(NSNumber*)getComponent:(PSSpecifier*)spec;
-(void)set:(NSNumber*)obj forComponent:(PSSpecifier*)spec;
-(void)updateColor:(NSArray*)colorArray;
-(void)preview;
-(void)reset;
-(void)dealloc;
-(void)suspend;
-(void)flushPreferences;
@end
@implementation GPPerPrioritySettingsController
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"Priority" target:self] retain];
		PSSpecifier* spec = self.specifier;
		j = [[spec propertyForKey:@"priorityLevel"] integerValue];
		self.title = spec.name;
		components = [[[[NSDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT] objectForKey:@"PerPrioritySettings"] objectAtIndex:j] mutableCopy];
	}
	return _specifiers;
}
-(NSNumber*)getComponent:(PSSpecifier*)spec {
	int val = [spec.identifier integerValue];
	[self updateColor:components];
	return [components objectAtIndex:val];
}
-(void)set:(NSNumber*)obj forComponent:(PSSpecifier*)spec {
	int val = [spec.identifier integerValue];
	[components replaceObjectAtIndex:val withObject:obj];
	[self updateColor:components];
}
-(void)updateColor:(NSArray*)colorArray {
	UIView* cell = [[self lastController] cachedCellForSpecifierID:@"previewBoxHere"];
	UIView* previewBox = [cell.subviews lastObject];
	BOOL newPreviousBox = previewBox.tag != 42;
	if (newPreviousBox)
		previewBox = [[UIView alloc] initWithFrame:CGRectMake(280, 20, 30, 15)];
	
	previewBox.backgroundColor = [UIColor colorWithRed:[[colorArray objectAtIndex:0] floatValue]
												 green:[[colorArray objectAtIndex:1] floatValue]
												  blue:[[colorArray objectAtIndex:2] floatValue]
												 alpha:[[colorArray objectAtIndex:3] floatValue]];
	previewBox.tag = 42;
	
	if (newPreviousBox) {
		[cell addSubview:previewBox];
		[previewBox release];
	}
}
-(void)preview {
	[self flushPreferences];
	NSBundle* myBundle = self.bundle;
	[bridge notifyWithTitle:LS(@"GriP Message Preview")
				description:[NSString stringWithFormat:LS(@"This is a preview of a <strong>%@</strong> GriP message."), self.title]
		   notificationName:@"Preview"
				   iconData:@"com.apple.Preferences"
				   priority:j-2
				   isSticky:NO
			   clickContext:nil];
}
-(void)flushPreferences {
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT];
	[[dict objectForKey:@"PerPrioritySettings"] replaceObjectAtIndex:j withObject:components];
	[dict writeToFile:GRIP_PREFDICT atomically:NO];
	[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil];
}
-(void)suspend {
	[self flushPreferences];
	[super suspend];
}
-(void)reset {
	for (int i = 0; i < 7; ++ i)
		[components replaceObjectAtIndex:i withObject:[NSNumber numberWithFloat:perPriorityDefaultSettings[j][i]]];
	[self reload];
}
-(void)dealloc {
	[components release];
	[super dealloc];
}
@end

//------------------------------------------------------------------------------
#pragma mark -

__attribute__((visibility("hidden")))
@interface MessageController : PSListController {
	NSMutableDictionary* msgdict;
	PSSpecifier* stealthSpec;
}
-(NSArray*)specifiers;
-(NSObject*)getMessage:(PSSpecifier*)spec;
-(void)set:(NSObject*)obj message:(PSSpecifier*)spec;
-(void)dealloc;
-(void)updateStealthSpec;
@end
@implementation MessageController
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"Message" target:self] retain];
		PSSpecifier* spec = self.specifier;
		msgdict = [spec propertyForKey:@"msgdict"];
		[self specifierForID:@"description"].name = [msgdict objectForKey:@"description"];
		self.title = spec.name;
		
		stealthSpec = [[self specifierForID:@"stealth"] retain];
		if ([[msgdict objectForKey:@"enabled"] boolValue])
			[self removeSpecifier:stealthSpec];
	}
	return _specifiers;
}
-(NSObject*)getMessage:(PSSpecifier*)spec { return [msgdict objectForKey:spec.identifier] ?: [NSNumber numberWithInteger:0]; }
-(void)set:(NSObject*)obj message:(PSSpecifier*)spec {
	NSString* iden = spec.identifier;
	[msgdict setObject:obj forKey:iden];
	if ([@"enabled" isEqualToString:iden])
		[self updateStealthSpec];
}
-(void)dealloc {
	[stealthSpec release];
	[super dealloc];
}
-(void)updateStealthSpec {
	if ([[msgdict objectForKey:@"enabled"] boolValue])
		[self removeSpecifier:stealthSpec animated:YES];
	else
		[self insertSpecifier:stealthSpec afterSpecifierID:@"enabled" animated:YES];
}
@end

//------------------------------------------------------------------------------
#pragma mark -

__attribute__((visibility("hidden")))
@interface TicketController : PSListController {
	NSMutableDictionary* dict;
	PSSpecifier* stealthSpec;
}
-(NSArray*)specifiers;
-(void)suspend;
-(void)dealloc;
-(NSObject*)getTicket:(PSSpecifier*)spec;
-(void)set:(NSObject*)obj ticket:(PSSpecifier*)spec;
-(void)removeSettings;
-(void)updateStealthSpec;
@end

@implementation TicketController
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		PSSpecifier* mySpec = self.specifier;
		
		NSString* filename = [mySpec propertyForKey:@"fn"];
		NSError* error = nil;
		NSData* data = [[NSData alloc] initWithContentsOfFile:filename options:0 error:&error];
		NSString* errDesc = [error localizedDescription];
		
		if (data != nil) {
			dict = [[NSPropertyListSerialization propertyListFromData:data mutabilityOption:kCFPropertyListMutableContainersAndLeaves format:NULL errorDescription:&errDesc] retain];
			[errDesc autorelease];
			[data release];
		}
		
		if (dict != nil) {
			_specifiers = [[self loadSpecifiersFromPlistName:@"Ticket" target:self] retain];
			NSMutableArray* secondPart = [[NSMutableArray alloc] init];
			
			NSMutableDictionary* messagesDict = [dict objectForKey:@"messages"];
			for (NSString* key in [[messagesDict allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
				NSMutableDictionary* msg = [messagesDict objectForKey:key];
				NSString* name = [msg objectForKey:@"friendlyName"] ?: key;
				PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:[MessageController class] cell:PSLinkCell edit:Nil];
				[spec setProperty:msg forKey:@"msgdict"];
				[secondPart addObject:spec];
			}
			[self insertContiguousSpecifiers:secondPart afterSpecifierID:@"_msgList"];
			[secondPart release];
			
		} else {
			_specifiers = [[NSArray alloc] initWithObjects:[PSSpecifier groupSpecifierWithName:errDesc], nil];
		}
		
		self.title = mySpec.name;
		
		stealthSpec = [[self specifierForID:@"stealth"] retain];
		if ([[dict objectForKey:@"enabled"] boolValue])
			[self removeSpecifier:stealthSpec];
	}
	return _specifiers;
}
-(void)dealloc {
	[dict release];
	[stealthSpec release];
	[super dealloc];
}
-(void)suspend {
	[dict writeToFile:[self.specifier propertyForKey:@"fn"] atomically:NO];
	[super suspend];
}
-(NSObject*)getTicket:(PSSpecifier*)spec {
	return [dict objectForKey:spec.identifier] ?: [NSNumber numberWithInteger:0];
}
-(void)set:(NSObject*)obj ticket:(PSSpecifier*)spec {
	NSString* iden = spec.identifier;
	[dict setObject:obj forKey:iden];
	if ([@"enabled" isEqualToString:iden])
		[self updateStealthSpec];
}
-(void)removeSettings {
	PSSpecifier* mySpec = self.specifier;
	NSError* err = nil;
	NSString* path = [mySpec propertyForKey:@"fn"];
	BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
	if (!success) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:[NSString stringWithFormat:LS(@"Cannot remove settings for %@"), mySpec.name]
					description:[NSString stringWithFormat:LS(@"Error: %@<br/><br/>Please delete <code>%@</code> manually."), err, path]
			   notificationName:@"Cannot remove settings"
					   iconData:@"com.apple.Preferences"
					   priority:0
					   isSticky:NO
				   clickContext:nil];
		[err release];
	} else {
		PSListController* ctrler = [self parentController];
		[dict release];
		dict = nil;
		[ctrler removeSpecifier:mySpec];
		[ctrler popController];
	}
}
-(void)updateStealthSpec {
	if ([[dict objectForKey:@"enabled"] boolValue])
		[self removeSpecifier:stealthSpec animated:YES];
	else
		[self insertSpecifier:stealthSpec afterSpecifierID:@"enabled" animated:YES];
}
@end

//------------------------------------------------------------------------------
#pragma mark -

@interface GPPrefsListController : PSListController<GrowlApplicationBridgeDelegate> {}
-(id)initForContentSize:(CGSize)size;
-(void)dealloc;
-(NSArray*)specifiers;
-(NSObject*)get:(PSSpecifier*)spec;
-(void)set:(NSObject*)obj with:(PSSpecifier*)spec;
-(void)preview;
-(void)updateCustomizeLinkTo:(NSString*)theme;

-(NSDictionary*)registrationDictionaryForGrowl;
-(NSString*)applicationNameForGrowl;
-(void)growlNotificationWasClicked:(NSObject*)context;
-(void)growlNotificationTimedOut:(NSObject*)context;
@end
@implementation GPPrefsListController
-(id)initForContentSize:(CGSize)size {
	if ((self = [super initForContentSize:size])) {
		bridge = [[GPApplicationBridge alloc] init];
		bridge.growlDelegate = self;
	}
	return self;
}
-(void)dealloc {
	[bridge release];
	[super dealloc];
}
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"GriP" target:self] retain];
		NSMutableArray* secondPart = [[NSMutableArray alloc] init];
		// populate the per-app settings.
		for (NSString* filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Library/GriP/Tickets/" error:NULL]) {
			if ([filename hasSuffix:@".ticket"]) {
				PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:[filename stringByDeletingPathExtension] target:nil set:nil get:nil detail:[TicketController class] cell:PSLinkCell edit:Nil];
				[spec setProperty:[@"/Library/GriP/Tickets/" stringByAppendingPathComponent:filename] forKey:@"fn"];
				[secondPart addObject:spec];
			}
		}
		[self addSpecifiersFromArray:secondPart];
		[secondPart release];
		[self updateCustomizeLinkTo:[[NSDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT] objectForKey:@"ActiveTheme"]];
	}
	return _specifiers;
}
-(NSObject*)get:(PSSpecifier*)spec {
	return [[NSDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT] objectForKey:spec.identifier];
}
-(void)set:(NSObject*)obj with:(PSSpecifier*)spec {
	NSString* specID = spec.identifier;
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:GRIP_PREFDICT];
	[dict setObject:obj forKey:specID];
	[dict writeToFile:GRIP_PREFDICT atomically:NO];
	// pass an empty data to force hard flush (close all windows)
	if ([@"ActiveTheme" isEqualToString:specID]) {
		[self updateCustomizeLinkTo:(NSString*)obj];
		[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:[NSData data]];
	} else
		[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil];
}
-(void)updateCustomizeLinkTo:(NSString*)theme {
	PSSpecifier* spec = [self specifierForID:@"Customize"];
	
	NSFileManager* fman = [NSFileManager defaultManager];
	[fman changeCurrentDirectoryPath:@"/Library/GriP/Themes/"];
	NSBundle* themeBundle = [NSBundle bundleWithPath:theme];
	NSString* prefName = [themeBundle objectForInfoDictionaryKey:@"PSBundle"];
	[spec setProperty:[NSNumber numberWithBool:(prefName != nil)] forKey:@"enabled"];
	[spec setProperty:[NSString stringWithFormat:@"/Library/GriP/Themes/%@/%@.bundle", theme, prefName] forKey:@"lazy-bundle"];
	[self reloadSpecifier:spec];
}
-(NSArray*)allThemeValues {
	NSFileManager* fman = [NSFileManager defaultManager];
	[fman changeCurrentDirectoryPath:@"/Library/GriP/Themes/"];
	return [[fman contentsOfDirectoryAtPath:@"." error:NULL] pathsMatchingExtensions:[NSArray arrayWithObjects:@"griptheme", nil]];
}
-(NSArray*)allThemeTitles {
	NSArray* allThemeValues = [self allThemeValues];
	NSMutableArray* resArray = [NSMutableArray arrayWithCapacity:[allThemeValues count]];
	
	for (NSString* path in allThemeValues)
		[resArray addObject:([[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [path stringByDeletingPathExtension])];
	
	return resArray;
}

-(void)preview {
	NSBundle* myBundle = self.bundle;
	[bridge notifyWithTitle:LS(@"GriP Message Preview")
				description:[NSString stringWithFormat:LS(@"This is a preview of a <strong>%@</strong> GriP message."), [[myBundle localizedStringForKey:@"Normal" value:nil table:@"GriP"] lowercaseString]]
		   notificationName:@"Preview"
				   iconData:@"com.apple.Preferences"
				   priority:0
				   isSticky:NO
			   clickContext:@"r"];
}

//------------------------------------------------------------------------------
#pragma mark -

-(NSDictionary*)registrationDictionaryForGrowl {
	NSArray* allNotifs = [NSArray arrayWithObjects:@"Preview", @"Message touched", @"Message ignored", @"Cannot remove settings", nil];
	return [NSDictionary dictionaryWithObjectsAndKeys:
			allNotifs, GROWL_NOTIFICATIONS_ALL,
			allNotifs, GROWL_NOTIFICATIONS_DEFAULT,
			[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Preview a GriP message.", @"Touched the preview message.", @"Ignored or closed the preview message.", @"Per-app settings cannot be removed.", nil]
										forKeys:allNotifs], GROWL_NOTIFICATIONS_DESCRIPTIONS,
			nil];
}
-(NSString*)applicationNameForGrowl { return @"GriP Preferences"; }
-(void)growlNotificationWasClicked:(NSObject*)context {
	if ([@"r" isEqualToString:(NSString*)context]) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:LS(@"Message touched")
					description:LS(@"You have touched the GriP preview message.")
			   notificationName:@"Message touched"
					   iconData:@"com.apple.Preferences"
					   priority:1
					   isSticky:NO
				   clickContext:@""];
	}
}
-(void)growlNotificationTimedOut:(NSObject*)context {
	if ([@"r" isEqualToString:(NSString*)context]) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:LS(@"Message ignored")
					description:LS(@"You have closed or ignored the GriP preview message.")
			   notificationName:@"Message touched"
					   iconData:@"com.apple.Preferences"
					   priority:-1
					   isSticky:NO
				   clickContext:@""];
	}
}

+(void)attentionClassDumpUser:(id)fp8 reverseEngineeringThisClassAndCallingPrivateMethodsIsNotFun:(id)fp12 andAllTheWholeSourceCodeAreAvailableOnTheWebForFreeToo:(id)fp16 soWhatTheHeckAreYouDoingHereHuh:(id)fp20 {
	NSLog(@"And this method at least *does* something.");
}
@end

//------------------------------------------------------------------------------
#pragma mark -

