// Ads, consent, analytics and the Remove Ads purchase for Physics Chain on iPhone/iPad: the same classes, methods and
// signals as the Android plugins (android_admob/: PCAdMob, PCFirebase, PCBilling). See src/autoload/ads.gd,
// analytics.gd and store.gd in the game.
//  - PCAdMob (Nov 27, 2026): interstitials; from Nov 28: rewarded "skip this level" ads and Google's consent message.
//  - PCFirebase (Nov 28): Google Analytics for Firebase and Crashlytics.
//  - PCStore (Nov 28): StoreKit, for the one-time Remove Ads purchase.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class PCAdMob : public RefCounted {
	GDCLASS(PCAdMob, RefCounted)

protected:
	static void _bind_methods();

public:
	// Child-directed, under-age-of-consent, max content rating for every request; starts the ad library.
	void setup(bool child_directed, const String &max_rating);
	// Loads one interstitial: interstitial_loaded or interstitial_failed(message).
	void load_interstitial(const String &unit_id);
	bool is_ready() const;
	// Shows the loaded interstitial: interstitial_closed when it's gone (also when it could not show).
	void show_interstitial();
	// Personalised ads only where the player agreed (or no consent is asked).
	void set_personalized(bool on);
	// Rewarded ads: rewarded_loaded / rewarded_failed(message), then rewarded_closed(earned) after showing.
	void load_rewarded(const String &unit_id);
	bool rewarded_ready() const;
	void show_rewarded();
	// Google's consent message (UMP), shown only where the law asks: consent_done(can_request_ads, analytics_ok,
	// personalized_ok).
	void request_consent();
	bool privacy_options_required() const;
	void show_privacy_options();
	~PCAdMob();
};

class PCFirebase : public RefCounted {
	GDCLASS(PCFirebase, RefCounted)

protected:
	static void _bind_methods();

public:
	// Starts Firebase with the app's settings (google_app_id, gcm_sender_id, api_key, project_id, bundle_id,
	// storage_bucket); Analytics collects nothing until start().
	void configure(const Dictionary &options);
	void start(bool analytics_ok, bool ads_ok);
	void log_event(const String &name, const Dictionary &params);
	void set_user_property(const String &name, const String &value);
	void crash_log(const String &message);
	void crash_key(const String &key, const String &value);
};

class PCStore : public RefCounted {
	GDCLASS(PCStore, RefCounted)

protected:
	static void _bind_methods();

public:
	// Looks up prices (price(id, text)) and reports what the player owns (owned(id)).
	void start(const PackedStringArray &ids);
	void buy(const String &product_id);
	// Restore purchases: owned(id) for each, purchase_failed(reason) if it fails.
	void restore();
	~PCStore();
};

} // namespace godot
