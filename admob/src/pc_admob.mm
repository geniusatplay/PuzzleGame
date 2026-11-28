#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include "pc_admob.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

// Google's libraries (Google-Mobile-Ads-SDK with its consent library UMP, FirebaseAnalytics, FirebaseCrashlytics) are
// linked into the app, not into this add-on, so their classes are found at run time: GADMobileAds, GADRequest,
// GADExtras, GADInterstitialAd, GADRewardedAd, UMPConsentInformation, UMPConsentForm, FIRApp, FIRAnalytics,
// FIRCrashlytics. Without a library its calls quietly do nothing and the game carries on. StoreKit is linked here.

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

static NSMutableDictionary<NSNumber *, NSNumber *> *pc_personal() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}
static NSMutableDictionary<NSNumber *, id> *pc_rewarded() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}
static NSMutableSet<NSNumber *> *pc_rewarded_loading() {
	static NSMutableSet *s = [NSMutableSet new];
	return s;
}
static NSMutableDictionary<NSNumber *, NSNumber *> *pc_earned() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}

// The rewarded ad's delegate: rewarded_closed(earned) when it's gone.
@interface PCRewardedDelegate : NSObject
@property(nonatomic, assign) uint64_t owner;
@end

@implementation PCRewardedDelegate
- (void)adDidDismissFullScreenContent:(id)ad {
	bool earned = [pc_earned()[@(self.owner)] boolValue];
	Object *o = ObjectDB::get_instance(self.owner);
	if (o) {
		o->call_deferred("emit_signal", String("rewarded_closed"), earned);
	}
}
- (void)ad:(id)ad didFailToPresentFullScreenContentWithError:(NSError *)error {
	NSLog(@"PCAdMob: rewarded ad did not show: %@", error.localizedDescription);
	Object *o = ObjectDB::get_instance(self.owner);
	if (o) {
		o->call_deferred("emit_signal", String("rewarded_closed"), false);
	}
}
@end

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

static id pc_request(NSNumber *key) {
	Class req_class = NSClassFromString(@"GADRequest");
	if (!req_class) {
		return nil;
	}
	id request = [[req_class alloc] init];
	if ([pc_personal()[key] boolValue]) {
		return request;
	}
	Class extras_class = NSClassFromString(@"GADExtras");
	SEL reg = NSSelectorFromString(@"registerAdNetworkExtras:");
	if (extras_class && [request respondsToSelector:reg]) {
		id extras = [[extras_class alloc] init];
		[extras setValue:@{ @"npa" : @"1" } forKey:@"additionalParameters"];
		((void (*)(id, SEL, id))objc_msgSend)(request, reg, extras);
	}
	return request;
}

void PCAdMob::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "child_directed", "max_rating"), &PCAdMob::setup);
	ClassDB::bind_method(D_METHOD("set_personalized", "on"), &PCAdMob::set_personalized);
	ClassDB::bind_method(D_METHOD("load_rewarded", "unit_id"), &PCAdMob::load_rewarded);
	ClassDB::bind_method(D_METHOD("rewarded_ready"), &PCAdMob::rewarded_ready);
	ClassDB::bind_method(D_METHOD("show_rewarded"), &PCAdMob::show_rewarded);
	ClassDB::bind_method(D_METHOD("request_consent"), &PCAdMob::request_consent);
	ClassDB::bind_method(D_METHOD("privacy_options_required"), &PCAdMob::privacy_options_required);
	ClassDB::bind_method(D_METHOD("show_privacy_options"), &PCAdMob::show_privacy_options);
	ADD_SIGNAL(MethodInfo("rewarded_loaded"));
	ADD_SIGNAL(MethodInfo("rewarded_failed", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("rewarded_closed", PropertyInfo(Variant::BOOL, "earned")));
	ADD_SIGNAL(MethodInfo("consent_done", PropertyInfo(Variant::BOOL, "can_request_ads"), PropertyInfo(Variant::BOOL, "analytics_ok"),
			PropertyInfo(Variant::BOOL, "personalized_ok")));
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
		SEL load = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
		id request = pc_request(key);
		if (!ad_class || !request || ![ad_class respondsToSelector:load]) {
			pc_emit(owner, "interstitial_failed", String("no ad library"), true);
			return;
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

void PCAdMob::set_personalized(bool on) {
	NSNumber *key = @((uint64_t)get_instance_id());
	dispatch_async(dispatch_get_main_queue(), ^{
		pc_personal()[key] = @(on);
	});
}

// ---- rewarded ads ("skip this level") ----

void PCAdMob::load_rewarded(const String &unit_id) {
	uint64_t owner = (uint64_t)get_instance_id();
	NSNumber *key = @(owner);
	NSString *unit = pc_ns(unit_id);
	dispatch_async(dispatch_get_main_queue(), ^{
		if (pc_rewarded()[key] || [pc_rewarded_loading() containsObject:key]) {
			return;
		}
		Class ad_class = NSClassFromString(@"GADRewardedAd");
		SEL load = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
		id request = pc_request(key);
		if (!ad_class || !request || ![ad_class respondsToSelector:load]) {
			pc_emit(owner, "rewarded_failed", String("no ad library"), true);
			return;
		}
		[pc_rewarded_loading() addObject:key];
		void (^done)(id, NSError *) = ^(id ad, NSError *error) {
			[pc_rewarded_loading() removeObject:key];
			if (!ad || error) {
				NSString *msg = error ? error.localizedDescription : @"no ad";
				pc_emit(owner, "rewarded_failed", String::utf8(msg.UTF8String), true);
				return;
			}
			PCRewardedDelegate *del = [PCRewardedDelegate new];
			del.owner = owner;
			pc_delegates()[@(-(int64_t)owner)] = (id)del;
			[ad setValue:del forKey:@"fullScreenContentDelegate"];
			pc_rewarded()[key] = ad;
			pc_emit(owner, "rewarded_loaded");
		};
		((void (*)(id, SEL, id, id, id))objc_msgSend)(ad_class, load, unit, request, done);
	});
}

bool PCAdMob::rewarded_ready() const {
	__block bool ready = false;
	NSNumber *key = @((uint64_t)get_instance_id());
	if ([NSThread isMainThread]) {
		ready = pc_rewarded()[key] != nil;
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			ready = pc_rewarded()[key] != nil;
		});
	}
	return ready;
}

void PCAdMob::show_rewarded() {
	uint64_t owner = (uint64_t)get_instance_id();
	NSNumber *key = @(owner);
	dispatch_async(dispatch_get_main_queue(), ^{
		id ad = pc_rewarded()[key];
		[pc_rewarded() removeObjectForKey:key];
		pc_earned()[key] = @NO;
		SEL present = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
		UIViewController *vc = pc_top_view_controller();
		Object *o = ObjectDB::get_instance(owner);
		if (!ad || !vc || ![ad respondsToSelector:present]) {
			if (o) {
				o->call_deferred("emit_signal", String("rewarded_closed"), false);
			}
			return;
		}
		void (^reward)(void) = ^{
			pc_earned()[key] = @YES;
		};
		((void (*)(id, SEL, id, id))objc_msgSend)(ad, present, vc, reward);
	});
}

// ---- consent (Google's User Messaging Platform) ----

static bool pc_purpose(NSString *purposes, int n) {
	return purposes && (int)purposes.length >= n && [purposes characterAtIndex:n - 1] == '1';
}

static id pc_consent_info() {
	Class ci = NSClassFromString(@"UMPConsentInformation");
	if (!ci || ![ci respondsToSelector:@selector(sharedInstance)]) {
		return nil;
	}
	return ((id(*)(id, SEL))objc_msgSend)(ci, @selector(sharedInstance));
}

static void pc_emit_consent(uint64_t owner) {
	id info = pc_consent_info();
	bool can = true;
	SEL can_sel = NSSelectorFromString(@"canRequestAds");
	if (info && [info respondsToSelector:can_sel]) {
		can = ((BOOL(*)(id, SEL))objc_msgSend)(info, can_sel);
	}
	bool analytics = true;
	bool personal = true;
	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	if ([d integerForKey:@"IABTCF_gdprApplies"] == 1) {
		// TCF purposes: 1 store/read on the device, 3 and 4 personalised ads, 7 ad measurement, 8 and 9 audience research
		NSString *p = [d stringForKey:@"IABTCF_PurposeConsents"];
		analytics = pc_purpose(p, 1) && (pc_purpose(p, 7) || pc_purpose(p, 8) || pc_purpose(p, 9));
		personal = pc_purpose(p, 1) && pc_purpose(p, 3) && pc_purpose(p, 4);
	}
	Object *o = ObjectDB::get_instance(owner);
	if (o) {
		o->call_deferred("emit_signal", String("consent_done"), can, analytics, personal);
	}
}

void PCAdMob::request_consent() {
	uint64_t owner = (uint64_t)get_instance_id();
	dispatch_async(dispatch_get_main_queue(), ^{
		id info = pc_consent_info();
		Class rp = NSClassFromString(@"UMPRequestParameters");
		Class form = NSClassFromString(@"UMPConsentForm");
		SEL upd = NSSelectorFromString(@"requestConsentInfoUpdateWithParameters:completionHandler:");
		SEL lp = NSSelectorFromString(@"loadAndPresentIfRequiredFromViewController:completionHandler:");
		if (!info || !rp || !form || ![info respondsToSelector:upd] || ![form respondsToSelector:lp]) {
			NSLog(@"PCAdMob: Google's consent library isn't in this build");
			pc_emit_consent(owner);
			return;
		}
		id params = [[rp alloc] init];
		void (^updated)(NSError *) = ^(NSError *err) {
			if (err) {
				NSLog(@"PCAdMob: consent info: %@", err.localizedDescription);
				pc_emit_consent(owner);
				return;
			}
			void (^shown)(NSError *) = ^(NSError *e2) {
				if (e2) {
					NSLog(@"PCAdMob: consent form: %@", e2.localizedDescription);
				}
				pc_emit_consent(owner);
			};
			((void (*)(id, SEL, id, id))objc_msgSend)(form, lp, pc_top_view_controller(), shown);
		};
		((void (*)(id, SEL, id, id))objc_msgSend)(info, upd, params, updated);
	});
}

bool PCAdMob::privacy_options_required() const {
	__block bool required = false;
	void (^check)(void) = ^{
		id info = pc_consent_info();
		SEL st = NSSelectorFromString(@"privacyOptionsRequirementStatus");
		if (info && [info respondsToSelector:st]) {
			// UMPPrivacyOptionsRequirementStatus: 0 unknown, 1 not required, 2 required
			required = ((NSInteger(*)(id, SEL))objc_msgSend)(info, st) == 2;
		}
	};
	if ([NSThread isMainThread]) {
		check();
	} else {
		dispatch_sync(dispatch_get_main_queue(), check);
	}
	return required;
}

void PCAdMob::show_privacy_options() {
	uint64_t owner = (uint64_t)get_instance_id();
	dispatch_async(dispatch_get_main_queue(), ^{
		Class form = NSClassFromString(@"UMPConsentForm");
		SEL sel = NSSelectorFromString(@"presentPrivacyOptionsFormFromViewController:completionHandler:");
		if (!form || ![form respondsToSelector:sel]) {
			return;
		}
		void (^done)(NSError *) = ^(NSError *e) {
			pc_emit_consent(owner);
		};
		((void (*)(id, SEL, id, id))objc_msgSend)(form, sel, pc_top_view_controller(), done);
	});
}

PCAdMob::~PCAdMob() {
	uint64_t owner = (uint64_t)get_instance_id();
	NSNumber *key = @(owner);
	dispatch_async(dispatch_get_main_queue(), ^{
		[pc_ads() removeObjectForKey:key];
		[pc_delegates() removeObjectForKey:key];
		[pc_delegates() removeObjectForKey:@(-(int64_t)owner)];
		[pc_loading() removeObject:key];
		[pc_rewarded() removeObjectForKey:key];
		[pc_rewarded_loading() removeObject:key];
		[pc_personal() removeObjectForKey:key];
		[pc_earned() removeObjectForKey:key];
	});
}

// ======================= PCFirebase =======================

static NSString *pc_ns_v(const Variant &v) {
	return pc_ns(v.stringify());
}

static id pc_to_ns(const Variant &v) {
	switch (v.get_type()) {
		case Variant::BOOL:
			return @((bool)v ? 1 : 0);
		case Variant::INT:
			return @((int64_t)v);
		case Variant::FLOAT:
			return @((double)v);
		default:
			return pc_ns_v(v);
	}
}

void PCFirebase::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "options"), &PCFirebase::configure);
	ClassDB::bind_method(D_METHOD("start", "analytics_ok", "ads_ok"), &PCFirebase::start);
	ClassDB::bind_method(D_METHOD("log_event", "name", "params"), &PCFirebase::log_event);
	ClassDB::bind_method(D_METHOD("set_user_property", "name", "value"), &PCFirebase::set_user_property);
	ClassDB::bind_method(D_METHOD("crash_log", "message"), &PCFirebase::crash_log);
	ClassDB::bind_method(D_METHOD("crash_key", "key", "value"), &PCFirebase::crash_key);
}

void PCFirebase::configure(const Dictionary &o) {
	NSString *app_id = pc_ns_v(o.get("google_app_id", ""));
	NSString *sender = pc_ns_v(o.get("gcm_sender_id", ""));
	NSString *api_key = pc_ns_v(o.get("api_key", ""));
	NSString *project = pc_ns_v(o.get("project_id", ""));
	NSString *bundle = pc_ns_v(o.get("bundle_id", ""));
	NSString *bucket = pc_ns_v(o.get("storage_bucket", ""));
	dispatch_async(dispatch_get_main_queue(), ^{
		Class app = NSClassFromString(@"FIRApp");
		Class opts = NSClassFromString(@"FIROptions");
		if (!app || !opts) {
			NSLog(@"PCFirebase: Firebase isn't in this build");
			return;
		}
		if (((id(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"defaultApp"))) {
			return;
		}
		@try {
			id op = ((id(*)(id, SEL, id, id))objc_msgSend)([opts alloc], NSSelectorFromString(@"initWithGoogleAppID:GCMSenderID:"), app_id, sender);
			[op setValue:api_key forKey:@"APIKey"];
			[op setValue:project forKey:@"projectID"];
			[op setValue:bundle forKey:@"bundleID"];
			[op setValue:bucket forKey:@"storageBucket"];
			((void (*)(id, SEL, id))objc_msgSend)(app, NSSelectorFromString(@"configureWithOptions:"), op);
		} @catch (NSException *e) {
			NSLog(@"PCFirebase: could not start Firebase: %@", e.reason);
		}
	});
}

static Class pc_analytics() {
	return NSClassFromString(@"FIRAnalytics");
}

void PCFirebase::start(bool analytics_ok, bool ads_ok) {
	dispatch_async(dispatch_get_main_queue(), ^{
		Class an = pc_analytics();
		if (!an) {
			return;
		}
		NSString *a = analytics_ok ? @"granted" : @"denied";
		NSString *ad = ads_ok ? @"granted" : @"denied";
		SEL consent = NSSelectorFromString(@"setConsent:");
		if ([an respondsToSelector:consent]) {
			((void (*)(id, SEL, id))objc_msgSend)(an, consent,
					@{ @"analytics_storage" : a, @"ad_storage" : ad, @"ad_user_data" : ad, @"ad_personalization" : ad });
		}
		((void (*)(id, SEL, BOOL))objc_msgSend)(an, NSSelectorFromString(@"setAnalyticsCollectionEnabled:"), analytics_ok);
	});
}

void PCFirebase::log_event(const String &name, const Dictionary &params) {
	NSString *n = pc_ns(name);
	NSMutableDictionary *p = [NSMutableDictionary new];
	Array keys = params.keys();
	for (int i = 0; i < keys.size(); i++) {
		p[pc_ns_v(keys[i])] = pc_to_ns(params[keys[i]]);
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		Class an = pc_analytics();
		if (an) {
			((void (*)(id, SEL, id, id))objc_msgSend)(an, NSSelectorFromString(@"logEventWithName:parameters:"), n, p);
		}
	});
}

void PCFirebase::set_user_property(const String &name, const String &value) {
	NSString *n = pc_ns(name);
	NSString *v = pc_ns(value);
	dispatch_async(dispatch_get_main_queue(), ^{
		Class an = pc_analytics();
		if (an) {
			((void (*)(id, SEL, id, id))objc_msgSend)(an, NSSelectorFromString(@"setUserPropertyString:forName:"), v, n);
		}
	});
}

static id pc_crashlytics() {
	Class c = NSClassFromString(@"FIRCrashlytics");
	if (!c) {
		return nil;
	}
	return ((id(*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"crashlytics"));
}

void PCFirebase::crash_log(const String &message) {
	NSString *m = pc_ns(message);
	dispatch_async(dispatch_get_main_queue(), ^{
		id c = pc_crashlytics();
		if (c) {
			((void (*)(id, SEL, id))objc_msgSend)(c, NSSelectorFromString(@"log:"), m);
		}
	});
}

void PCFirebase::crash_key(const String &key, const String &value) {
	NSString *k = pc_ns(key);
	NSString *v = pc_ns(value);
	dispatch_async(dispatch_get_main_queue(), ^{
		id c = pc_crashlytics();
		if (c) {
			((void (*)(id, SEL, id, id))objc_msgSend)(c, NSSelectorFromString(@"setCustomValue:forKey:"), v, k);
		}
	});
}

// ======================= PCStore (StoreKit) =======================

@interface PCStoreHelper : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@property(nonatomic, assign) uint64_t owner;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SKProduct *> *products;
@property(nonatomic, strong) SKProductsRequest *request;
@end

static void pc_store_emit(uint64_t owner, const char *signal, NSString *a, NSString *b = nil) {
	Object *o = ObjectDB::get_instance(owner);
	if (!o) {
		return;
	}
	if (b) {
		o->call_deferred("emit_signal", String(signal), String::utf8(a.UTF8String), String::utf8(b.UTF8String));
	} else {
		o->call_deferred("emit_signal", String(signal), String::utf8(a.UTF8String));
	}
}

@implementation PCStoreHelper
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
	for (SKProduct *p in response.products) {
		self.products[p.productIdentifier] = p;
		NSNumberFormatter *f = [NSNumberFormatter new];
		f.numberStyle = NSNumberFormatterCurrencyStyle;
		f.locale = p.priceLocale;
		pc_store_emit(self.owner, "price", p.productIdentifier, [f stringFromNumber:p.price] ?: @"");
	}
	for (NSString *bad in response.invalidProductIdentifiers) {
		NSLog(@"PCStore: unknown product %@", bad);
	}
}
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
	NSLog(@"PCStore: product lookup failed: %@", error.localizedDescription);
}
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
	for (SKPaymentTransaction *t in transactions) {
		switch (t.transactionState) {
			case SKPaymentTransactionStatePurchased:
			case SKPaymentTransactionStateRestored:
				pc_store_emit(self.owner, "owned", t.payment.productIdentifier);
				[queue finishTransaction:t];
				break;
			case SKPaymentTransactionStateFailed:
				pc_store_emit(self.owner, "purchase_failed",
						t.error.code == SKErrorPaymentCancelled ? @"cancelled" : (t.error.localizedDescription ?: @"failed"));
				[queue finishTransaction:t];
				break;
			default:
				break; // purchasing, or deferred (waiting for a parent's approval)
		}
	}
}
- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
	pc_store_emit(self.owner, "purchase_failed", error.code == SKErrorPaymentCancelled ? @"cancelled" : (error.localizedDescription ?: @"failed"));
}
@end

static NSMutableDictionary<NSNumber *, PCStoreHelper *> *pc_store_helpers() {
	static NSMutableDictionary *d = [NSMutableDictionary new];
	return d;
}

static PCStoreHelper *pc_store_helper(uint64_t owner) {
	NSNumber *key = @(owner);
	PCStoreHelper *h = pc_store_helpers()[key];
	if (!h) {
		h = [PCStoreHelper new];
		h.owner = owner;
		h.products = [NSMutableDictionary new];
		pc_store_helpers()[key] = h;
		[[SKPaymentQueue defaultQueue] addTransactionObserver:h];
	}
	return h;
}

void PCStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "ids"), &PCStore::start);
	ClassDB::bind_method(D_METHOD("buy", "product_id"), &PCStore::buy);
	ClassDB::bind_method(D_METHOD("restore"), &PCStore::restore);
	ADD_SIGNAL(MethodInfo("price", PropertyInfo(Variant::STRING, "product_id"), PropertyInfo(Variant::STRING, "text")));
	ADD_SIGNAL(MethodInfo("owned", PropertyInfo(Variant::STRING, "product_id")));
	ADD_SIGNAL(MethodInfo("purchase_failed", PropertyInfo(Variant::STRING, "reason")));
}

void PCStore::start(const PackedStringArray &ids) {
	uint64_t owner = (uint64_t)get_instance_id();
	NSMutableSet *set = [NSMutableSet new];
	for (int i = 0; i < ids.size(); i++) {
		[set addObject:pc_ns(ids[i])];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		PCStoreHelper *h = pc_store_helper(owner);
		h.request = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
		h.request.delegate = h;
		[h.request start];
	});
}

void PCStore::buy(const String &product_id) {
	uint64_t owner = (uint64_t)get_instance_id();
	NSString *pid = pc_ns(product_id);
	dispatch_async(dispatch_get_main_queue(), ^{
		PCStoreHelper *h = pc_store_helper(owner);
		SKProduct *p = h.products[pid];
		if (!p || ![SKPaymentQueue canMakePayments]) {
			pc_store_emit(owner, "purchase_failed", p ? @"payments are turned off on this device" : @"unavailable");
			return;
		}
		[[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:p]];
	});
}

void PCStore::restore() {
	uint64_t owner = (uint64_t)get_instance_id();
	dispatch_async(dispatch_get_main_queue(), ^{
		pc_store_helper(owner);
		[[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
	});
}

PCStore::~PCStore() {
	NSNumber *key = @((uint64_t)get_instance_id());
	dispatch_async(dispatch_get_main_queue(), ^{
		PCStoreHelper *h = pc_store_helpers()[key];
		if (h) {
			[[SKPaymentQueue defaultQueue] removeTransactionObserver:h];
			[pc_store_helpers() removeObjectForKey:key];
		}
	});
}
