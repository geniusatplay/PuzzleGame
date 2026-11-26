// Game Center sign-in for Physics Chain's online saves (Nov 26, 2026). See src/autoload/cloud.gd in the game.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

class PCGameCenter : public RefCounted {
	GDCLASS(PCGameCenter, RefCounted)

protected:
	static void _bind_methods();

public:
	// Signs in with Game Center (Apple's own sheet if needed). Answers with authenticated(ok, team_player_id).
	void authenticate();
	// A signature Apple makes for this player and this app, for the studio's server. Answers with proof(dict),
	// empty when it failed: {public_key_url, signature, salt (base64), timestamp, player_id, bundle_id}.
	void fetch_proof();
	bool is_authenticated() const;
	void emit_authenticated(bool ok);
};

} // namespace godot
