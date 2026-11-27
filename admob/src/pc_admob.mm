#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include "pc_admob.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

// Google's ad library (Google-Mobile-Ads-SDK) is linked into the app, not into this add-on, so its classes are found
// at run time: GADMobileAds, GADRequest, GADExtras, GADInterstitialAd. Without the library every call quietly does
// nothing and the game carries on with no ads.

@interface PCAdMobDelegate : NSObject
@property(nonatomic, assign) uint64_t owner;
@end

static void pc_emit(uint64_t owner, const char *signal, const String &arg = String(), bool with_arg = false) {
	Object *o = ObjectDB::get_instance(owner);
	if (!o) {
		return;
	}
	if (with_arg) {
		o->call_deferred("emit_signal", String(signal), arg);
	} else {
		o->call_deferred("emit_signal", String(signal));
	}
}

@implementation PCAdMobDelegate
- (void)adDidDismissFullScreenContent:(id)ad {
	pc_emit(self.owner, "interstitial_closed");
}
- (void)ad:(id)ad didFailToPresentFullScreenContentWithError:(NSError *)error {
	NSLog(@"PCAdMob: ad did not show: %@", error.localizedDescription);
	pc_emit(self.owner, "interstitial_closed");
}
@end

static NSMutableDictionary<NSNumber *, id> *pc_ads() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}
static NSMutableDictionary<NSNumber *, PCAdMobDelegate *> *pc_delegates() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}
static NSMutableSet<NSNumber *> *pc_loading() {
	static NSMutableSet *s = [NSMutableSet new];
	return s;
}

static UIViewController *pc_top_view_controller() {
	UIWindow *win = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				win = w;
				break;
			}
		}
		if (!win && ((UIWindowScene *)scene).windows.count > 0) {
			win = ((UIWindowScene *)scene).windows.firstObject;
		}
		if (win) {
			break;
		}
	}
	UIViewController *vc = win.rootViewController;
	while (vc.presentedViewController) {
		vc = vc.presentedViewController;
	}
	return vc;
}

static NSString *pc_ns(const String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()];
}

static id pc_shared_ads() {
	Class c = NSClassFromString(@"GADMobileAds");
	if (!c || ![c respondsToSelector:@selector(sharedInstance)]) {
		return nil;
	}
	return ((id(*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
}

void PCAdMob::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "child_directed", "max_rating"), &PCAdMob::setup);
	ClassDB::bind_method(D_METHOD("load_interstitial", "unit_id"), &PCAdMob::load_interstitial);
	ClassDB::bind_method(D_METHOD("is_ready"), &PCAdMob::is_ready);
	ClassDB::bind_method(D_METHOD("show_interstitial"), &PCAdMob::show_interstitial);
	ADD_SIGNAL(MethodInfo("interstitial_loaded"));
	ADD_SIGNAL(MethodInfo("interstitial_failed", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("interstitial_closed"));
}

void PCAdMob::setup(bool child_directed, const String &max_rating) {
	NSString *rating = max_rating.is_empty() ? @"G" : pc_ns(max_rating);
	dispatch_async(dispatch_get_main_queue(), ^{
		id ads = pc_shared_ads();
		if (!ads) {
			NSLog(@"PCAdMob: Google Mobile Ads isn't in this build");
			return;
		}
		id conf = [ads valueForKey:@"requestConfiguration"];
		@try {
			if (child_directed) {
				[conf setValue:@YES forKey:@"tagForChildDirectedTreatment"];
				[conf setValue:@YES forKey:@"tagForUnderAgeOfConsent"];
			}
			[conf setValue:rating forKey:@"maxAdContentRating"];
		} @catch (NSException *e) {
			NSLog(@"PCAdMob: could not set the request settings: %@", e.reason);
		}
		SEL start = NSSelectorFromString(@"startWithCompletionHandler:");
		if ([ads respondsToSelector:start]) {
			((void (*)(id, SEL, id))objc_msgSend)(ads, start, nil);
		}
	});
}

void PCAdMob::load_interstitial(const String &unit_id) {
	uint64_t owner = (uint64_t)get_instance_id();
	NSNumber *key = @(owner);
	NSString *unit = pc_ns(unit_id);
	dispatch_async(dispatch_get_main_queue(), ^{
		if (pc_ads()[key] || [pc_loading() containsObject:key]) {
			return;
		}
		Class ad_class = NSClassFromString(@"GADInterstitialAd");
		Class req_class = NSClassFromString(@"GADRequest");
		SEL load = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
		if (!ad_class || !req_class || ![ad_class respondsToSelector:load]) {
			pc_emit(owner, "interstitial_failed", String("no ad library"), true);
			return;
		}
		id request = [[req_class alloc] init];
		Class extras_class = NSClassFromString(@"GADExtras");
		SEL reg = NSSelectorFromString(@"registerAdNetworkExtras:");
		if (extras_class && [request respondsToSelector:reg]) {
			id extras = [[extras_class alloc] init];
			[extras setValue:@{ @"npa" : @"1" } forKey:@"additionalParameters"];
			((void (*)(id, SEL, id))objc_msgSend)(request, reg, extras);
		}
		[pc_loading() addObject:key];
		void (^done)(id, NSError *) = ^(id ad, NSError *error) {
			[pc_loading() removeObject:key];
			if (!ad || error) {
				NSString *msg = error ? error.localizedDescription : @"no ad";
				pc_emit(owner, "interstitial_failed", String::utf8(msg.UTF8String), true);
				return;
			}
			PCAdMobDelegate *del = [PCAdMobDelegate new];
			del.owner = owner;
			pc_delegates()[key] = del;
			[ad setValue:del forKey:@"fullScreenContentDelegate"];
			pc_ads()[key] = ad;
			pc_emit(owner, "interstitial_loaded");
		};
		((void (*)(id, SEL, id, id, id))objc_msgSend)(ad_class, load, unit, request, done);
	});
}

bool PCAdMob::is_ready() const {
	__block bool ready = false;
	NSNumber *key = @((uint64_t)get_instance_id());
	if ([NSThread isMainThread]) {
		ready = pc_ads()[key] != nil;
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			ready = pc_ads()[key] != nil;
		});
	}
	return ready;
}

void PCAdMob::show_interstitial() {
	uint64_t owner = (uint64_t)get_instance_id();
	NSNumber *key = @(owner);
	dispatch_async(dispatch_get_main_queue(), ^{
		id ad = pc_ads()[key];
		[pc_ads() removeObjectForKey:key];
		SEL present = NSSelectorFromString(@"presentFromRootViewController:");
		UIViewController *vc = pc_top_view_controller();
		if (!ad || !vc || ![ad respondsToSelector:present]) {
			pc_emit(owner, "interstitial_closed");
			return;
		}
		((void (*)(id, SEL, id))objc_msgSend)(ad, present, vc);
	});
}

PCAdMob::~PCAdMob() {
	NSNumber *key = @((uint64_t)get_instance_id());
	dispatch_async(dispatch_get_main_queue(), ^{
		[pc_ads() removeObjectForKey:key];
		[pc_delegates() removeObjectForKey:key];
		[pc_loading() removeObject:key];
	});
}
