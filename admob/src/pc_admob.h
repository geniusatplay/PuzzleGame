// AdMob interstitials between levels for Physics Chain (Nov 27, 2026). See src/autoload/ads.gd in the game; the same
// methods and signals as the Android plugin (android_admob/).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
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
	~PCAdMob();
};

} // namespace godot
