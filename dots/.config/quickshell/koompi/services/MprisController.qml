pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property list<MprisPlayer> players: Mpris.players.values.filter(player => isRealPlayer(player));
	property MprisPlayer trackedPlayer: null;
	property MprisPlayer activePlayer: trackedPlayer ?? players[0] ?? null;
	signal trackChanged(reverse: bool);

	property bool __reverse: false;

	property var activeTrack;

	readonly property bool hasActivePlasmaIntegration: Mpris.players.values.some(
		p => p.dbusName?.startsWith('org.mpris.MediaPlayer2.plasma-browser-integration')
	)
	function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        return (
            // Remove native browser buses only if plasma-browser-integration is actually active on D-Bus
            !(hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.firefox')) && !(hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.chromium')) &&
            // playerctld just copies other buses and we don't need duplicates
            !player.dbusName?.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(player.dbusName?.endsWith('.mpd') && !player.dbusName.endsWith('MediaPlayer2.mpd')));
    }

	// Original stuff from fox below
	Instantiator {
		model: Mpris.players;

		Connections {
			required property MprisPlayer modelData;
			target: modelData;

			Component.onCompleted: {
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
			}

			Component.onDestruction: {
				if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
					for (const player of Mpris.players.values) {
						if (player.playbackState.isPlaying) {
							root.trackedPlayer = player;
							break;
						}
					}

					if (trackedPlayer == null && Mpris.players.values.length != 0) {
						trackedPlayer = Mpris.players.values[0];
					}
				}
			}

			function onPlaybackStateChanged() {
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
		}
	}

	Connections {
		target: activePlayer

		function onPostTrackChanged() {
			root.updateTrack();
		}

		function onTrackArtUrlChanged() {
			// console.log("arturl:", activePlayer.trackArtUrl)
			// root.updateTrack();
			if (root.activePlayer.uniqueId == root.activeTrack.uniqueId && root.activePlayer.trackArtUrl != root.activeTrack.artUrl) {
				// cantata likes to send cover updates *BEFORE* updating the track info.
				// as such, art url changes shouldn't be able to break the reverse animation
				const r = root.__reverse;
				root.updateTrack();
				root.__reverse = r;

			}
		}
	}

	onActivePlayerChanged: { this.updateTrack(); this.__resetStale(); }

	function updateTrack() {
		//console.log(`update: ${this.activePlayer?.trackTitle ?? ""} : ${this.activePlayer?.trackArtists}`)
		this.activeTrack = {
			uniqueId: this.activePlayer?.uniqueId ?? 0,
			artUrl: this.activePlayer?.trackArtUrl ?? "",
			title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
			artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
			album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
		};

		this.trackChanged(__reverse);
		this.__reverse = false;
	}

	property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
	// True only when the active player has a live session with real metadata.
	// Browsers leave a Stopped player with stale title/art around after playback
	// ends; UI should gate visibility on this rather than on a non-empty title.
	readonly property bool hasActiveMedia: !!this.activePlayer
		&& this.activePlayer.playbackState !== MprisPlaybackState.Stopped
		&& (this.activePlayer.trackTitle ?? "").length > 0
		&& !this.activePlayerStale;

	// --- Stale plasma-browser-integration detection --------------------------
	// plasma-browser-integration can stick reporting Playing with a *frozen*
	// real position after a tab's media ends, leaving a phantom on the bar.
	// Quickshell extrapolates MprisPlayer.position for anything it thinks is
	// Playing, so the freeze is invisible in-process; we read the raw D-Bus
	// position out-of-band (playerctl) and treat Playing-but-frozen as dead.
	// Scoped to plasma only so native players (mpd/spotify) are never polled;
	// if playerctl is absent the probe yields nothing and the phantom shows.
	property bool activePlayerStale: false;
	readonly property bool activeIsPlasma: (this.activePlayer?.dbusName ?? "")
		.startsWith("org.mpris.MediaPlayer2.plasma-browser-integration");
	property real __lastRealPos: -1;
	property int __frozenPolls: 0;
	function __resetStale() {
		this.__lastRealPos = -1;
		this.__frozenPolls = 0;
		this.activePlayerStale = false;
	}

	property bool playerctlAvailable: false
	Process {
		running: true
		command: ["which", "playerctl"]
		onExited: (exitCode, exitStatus) => root.playerctlAvailable = (exitCode === 0)
	}

	Process {
		id: realPositionProbe
		property string busSuffix: ""
		command: ["playerctl", "-p", busSuffix, "position"]
		stdout: StdioCollector {
			id: realPosCollector
			onStreamFinished: {
				const pos = parseFloat(realPosCollector.text.trim());
				if (isNaN(pos)) return; // playerctl missing or no value -> leave as-is
				if (!(root.activePlayer?.isPlaying ?? false)) { root.__resetStale(); return; }
				if (root.__lastRealPos >= 0 && Math.abs(pos - root.__lastRealPos) < 0.05) {
					root.__frozenPolls++;
				} else {
					root.__frozenPolls = 0;
				}
				root.__lastRealPos = pos;
				root.activePlayerStale = root.__frozenPolls >= 2; // frozen across 3 polls (~9s)
			}
		}
	}

	Timer {
		interval: 3000
		repeat: true
		running: root.playerctlAvailable && root.activeIsPlasma && (root.activePlayer?.isPlaying ?? false)
		onRunningChanged: if (!running) root.__resetStale();
		onTriggered: {
			realPositionProbe.busSuffix = root.activePlayer.dbusName.replace("org.mpris.MediaPlayer2.", "");
			realPositionProbe.running = true;
		}
	}

	property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
	function togglePlaying() {
		if (this.canTogglePlaying) this.activePlayer.togglePlaying();
	}

	property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
	function previous() {
		if (this.canGoPrevious) {
			this.__reverse = true;
			this.activePlayer.previous();
		}
	}

	property bool canGoNext: this.activePlayer?.canGoNext ?? false;
	function next() {
		if (this.canGoNext) {
			this.__reverse = false;
			this.activePlayer.next();
		}
	}

	property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;

	property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
	property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
	function setLoopState(loopState: var) {
		if (this.loopSupported) {
			this.activePlayer.loopState = loopState;
		}
	}

	property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
	property bool hasShuffle: this.activePlayer?.shuffle ?? false;
	function setShuffle(shuffle: bool) {
		if (this.shuffleSupported) {
			this.activePlayer.shuffle = shuffle;
		}
	}

	function setActivePlayer(player: MprisPlayer) {
		const targetPlayer = player ?? Mpris.players[0];
		console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

		if (targetPlayer && this.activePlayer) {
			this.__reverse = Mpris.players.indexOf(targetPlayer) < Mpris.players.indexOf(this.activePlayer);
		} else {
			// always animate forward if going to null
			this.__reverse = false;
		}

		this.trackedPlayer = targetPlayer;
	}

	IpcHandler {
		target: "mpris"

		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}

		function playPause(): void { root.togglePlaying(); }
		function previous(): void { root.previous(); }
		function next(): void { root.next(); }
	}
}
