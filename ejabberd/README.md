# captcha.sh

A hardened split-image CAPTCHA generator written in pure POSIX shell, using ImageMagick. Built specifically to protect ejabberd In-Band Registration (IBR) from automated bot signups.

---

## Background

Open IBR on an ejabberd server is a bot magnet. Even with rate limiting, bots will chew through registrations fast enough to be a real problem. This script generates a CAPTCHA image that gets served during the registration flow, requiring the user to read and enter a 6-digit code before their account is created.

The design goal was something that bots find hard to solve, while remaining straightforward for real users.

---

## How it works

The script takes a 6-digit string as input and outputs a PNG image to stdout. The image contains three shuffled segments, each showing two digits. A header strip at the top tells the user what order to read the segments in, using colored dots as markers.

The reading order is encoded in the color of the dot, not the left-to-right position of the segment. The segments are shuffled randomly on every generation, so positional guessing gives no advantage.

**Flow:**

1. Your registration handler generates a random 6-digit code
2. It calls `captcha.sh <code>` and serves the PNG to the user
3. The user reads the image and types the digits in the order shown
4. You validate their input against the original code before creating the account

---

## Security layers

The defenses are stacked so that breaking one does not break the CAPTCHA.

**Segment shuffling** The three digit pairs are placed in random visual positions on every generation. Position alone carries no information about the correct order.

**Color-encoded reading order**  The header shows three colored dots with arrows. The color of the dot above a segment tells you where that segment sits in the sequence. The color-to-position mapping is reshuffled each time.

**Color jitter** The dot colors (roughly red, green, blue) are shifted by a random amount of up to 20 per RGB channel on every render. They still look like red, green, and blue to a human. Fixed-threshold color detection fails because the exact RGB values are never the same twice.

**Header noise** The header strip gets light random noise and a mild wave distortion, so bots cannot cleanly extract dot colors from a known pixel region.

**Random digit colors** Each digit pair is rendered in a different saturated color chosen randomly from a palette. No two segments in the same image share a color.

**Randomized digit placement** The horizontal position of the digits shifts across a wide range each render, making it harder to build a reliable crop box for OCR.

**Wave distortion** Two independent wave passes are applied to each segment with randomized amplitude and wavelength. The wide parameter range defeats inverters trained on a specific distortion profile.

**Arc interference** Two random arcs pass through the digit area in each segment, disrupting character segmentation more effectively than straight lines or uniform noise.

**Background noise** Impulse noise is added to every segment and the header before wave distortion is applied.

---

## Requirements

- Any POSIX-compatible shell
- ImageMagick (`convert` at `/usr/bin/convert`)
- DejaVu Sans fonts

On Debian/Ubuntu:

```bash
apt install imagemagick fonts-dejavu
```

---

## Usage

```bash
./captcha.sh <6-digit-code> > captcha.png
```

The script writes the PNG to stdout. If no input is provided it exits with code 1.

**Quick test:**

```bash
./captcha.sh 391047 > /tmp/test.png && xdg-open /tmp/test.png
```

---

## ejabberd integration

ejabberd supports external CAPTCHA scripts via the `captcha_cmd` option. Set it in your `ejabberd.yml`:

```yaml
captcha_cmd: /path/to/captcha.sh
captcha_url: https://your.xmpp.server/captcha
captcha_limit: 5
```

ejabberd will call the script with the code it generates, serve the image to the registering user, and validate the response automatically. No custom handler needed.

Make sure the script is executable and that the `ejabberd` user can run it:

```bash
chmod +x /path/to/captcha.sh
```

---

## Output format

The final image is approximately 300x94 pixels:

- A 300x22 header strip with the reading-order legend
- Three 100x72 segment tiles side by side

Output is a PNG written to stdout at 8-bit depth.

---

## Limitations

This raises the cost of automated solving significantly, but a determined attacker with enough samples could train a model against it. For better protection, combine it with rate limiting, IP reputation checks (e.g. AbuseIPDB), and fail2ban rules on your ejabberd registration endpoint.

The script requires ImageMagick's `convert` to support `-wave`, `-annotate`, `+noise`, and `arc` draw operations. Older ImageMagick versions may behave differently.

---

## License

MIT
