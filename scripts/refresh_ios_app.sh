#!/usr/bin/env bash
# Keep the app alive on the iPhone past the 7-day free-provisioning limit.
#
# A free Apple account gets a provisioning profile valid for 7 days; the
# signing certificate itself lasts a year. Rebuilding mints a fresh profile,
# so reinstalling before the deadline keeps the app launchable. Installing
# over the top preserves the app's Documents directory, so training data,
# ratings and preferences survive.
#
# Runs daily via launchd and does nothing until the profile is close to
# expiring. Requires: Mac awake, and the iPhone reachable (cable, or Wi-Fi
# with "Connect via Network" ticked in Xcode > Window > Devices).

set -uo pipefail

DEVICE_ID="F3ABE99B-E336-50C5-9428-C691BA0B202B"
BUNDLE_ID="com.easistent.mealpicker"
PROJECT="/Users/lovrobor/meal-picker"
RENEW_WITHIN_DAYS=3
LOG="$PROJECT/build/refresh.log"

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$(dirname "$LOG")"
say() { echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$LOG"; }

cd "$PROJECT" || { say "FAIL: project dir missing"; exit 1; }

# ── How long is left on the current profile? ──
profile=$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
if [ -n "$profile" ]; then
  exp=$(security cms -D -i "$profile" 2>/dev/null \
        | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  if [ -n "$exp" ]; then
    exp_s=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$exp" "+%s" 2>/dev/null)
    now_s=$(date "+%s")
    left=$(( (exp_s - now_s) / 86400 ))
    say "profile expires $exp (${left}d left)"
    if [ "$left" -gt "$RENEW_WITHIN_DAYS" ]; then
      say "skip: more than ${RENEW_WITHIN_DAYS}d remaining"
      exit 0
    fi
  fi
fi

# ── Is the phone reachable? ──
#
# Do not pattern-match the State column. Over Wi-Fi an idle device reads
# "available (paired)" and only flips to "connected" once something has woken
# the tunnel, so grepping for "connected" skips a perfectly reachable phone.
# Probing establishes the tunnel, which is the only honest test of whether an
# install would actually succeed.
if ! xcrun devicectl device info details --device "$DEVICE_ID" >/dev/null 2>&1; then
  say "WAIT: iPhone not reachable - will retry on the next run"
  osascript -e 'display notification "Connect the iPhone (same Wi-Fi, or cable) so the meal picker can be renewed." with title "Meal Picker expires soon"' 2>/dev/null
  exit 0
fi
say "iPhone reachable"

# ── Force a genuinely new profile ──
#
# Rebuilding alone is not enough: Xcode reuses a profile that is still valid,
# so the expiry does not move and the app dies anyway. The profile is dated
# from its creation, so deleting it makes Xcode mint one with a full 7 days.
# Only profiles for this app are removed, never the whole store.
for prof in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  [ -e "$prof" ] || continue
  if security cms -D -i "$prof" 2>/dev/null | grep -q "$BUNDLE_ID"; then
    rm -f "$prof"
    say "removed stale profile $(basename "$prof")"
  fi
done

# ── Rebuild with a fresh profile and install over the existing app ──
say "renewing..."
if ! flutter build ios --release >> "$LOG" 2>&1; then
  say "FAIL: flutter build"
  osascript -e 'display notification "Rebuild failed — see build/refresh.log" with title "Meal Picker renewal failed"' 2>/dev/null
  exit 1
fi

if xcrun devicectl device install app --device "$DEVICE_ID" \
      build/ios/iphoneos/Runner.app >> "$LOG" 2>&1; then
  newp=$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
  newexp=$(security cms -D -i "$newp" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  say "OK: reinstalled, now expires $newexp"
  osascript -e 'display notification "Renewed for another 7 days." with title "Meal Picker"' 2>/dev/null
else
  say "FAIL: install"
  osascript -e 'display notification "Install failed — see build/refresh.log" with title "Meal Picker renewal failed"' 2>/dev/null
  exit 1
fi
