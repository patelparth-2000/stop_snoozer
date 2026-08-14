---
title: StopSnoozer Privacy Policy
---

# StopSnoozer — Privacy Policy

**Last updated:** 10 August 2026
**Applies to:** StopSnoozer for Android (`com.stopsnoozer.app`), version 1.0.0 onwards

StopSnoozer is published by **Parth Patel**, an individual developer based in the
United Kingdom. Contact: **patelparthm2000@gmail.com**.

This policy explains what StopSnoozer does with your data. The short version is
that almost nothing leaves your phone, and the two things that do are described
in full below.

---

## What StopSnoozer is

StopSnoozer is a commuter alarm. You choose a stop or station; the app wakes you
when you get there. Because much of the London Underground has no GPS and
patchy mobile signal, the app also tracks your progress using your phone's
motion and pressure sensors, which work offline.

---

## Location data

### What we use, and why

StopSnoozer uses your device's location to work out when you have reached your
destination stop, so it can fire your alarm.

### Background location

**StopSnoozer collects location data to detect when you reach your destination
stop and wake you with an alarm, even when the app is closed or not in use.**

This is the core purpose of the app. An alarm that only works while you are
looking at the screen would be useless — the point is that you can sleep, read,
or put your phone away. When a journey is running, StopSnoozer runs a foreground
service with a permanent notification, so you can always see that tracking is
active and stop it in one tap.

Before Android asks you for the "Allow all the time" permission, StopSnoozer
shows you an in-app screen explaining exactly this. If you decline, the app
still works — alarms will only fire reliably while the app is open.

### Where location goes

Your location is processed **on your device only**. It is never uploaded to us,
never sold, never shared with advertisers, and never used to build a profile of
you. We operate no servers and hold no account for you — there is nowhere for
your location to be sent.

---

## Sensor data

While a journey is running, StopSnoozer reads:

| Sensor | Used for |
|---|---|
| Barometer (air pressure) | Detecting descent into and ascent out of tunnels, and matching station platform depth |
| Accelerometer | Detecting when the train is moving, braking and stopped |
| Wi-Fi presence and mobile cell identifiers | Optional. Corroborating which station you are at (see below) |

All of this is processed on your device and none of it is transmitted.

---

## Wi-Fi and mobile-cell identifiers — optional, and only with consent

StopSnoozer can read the identifiers (BSSIDs and cell IDs) of nearby Wi-Fi
access points and mobile cells, and remember which ones it saw at which station,
so it recognises that station faster on later journeys.

**This is off by default.** The app asks for your explicit consent before it
reads or stores any of it, and it works perfectly well without it — arrival
detection falls back to the pressure and motion sensors and journey timing.

Under the UK Privacy and Electronic Communications Regulations (PECR),
regulation 6, consent is required to *access* information stored on your
device's terminal equipment, whether or not that information is then sent
anywhere. That is why we ask, even though nothing is transmitted.

If you consent:

- The identifiers are stored in the app's private database on your phone.
- They are never transmitted anywhere.
- Entries not seen for 120 days are automatically deleted.
- You can withdraw consent at any time in **System Health → Privacy & Learned
  Data**. Withdrawing consent immediately erases everything learned under it.
- You can erase the learned data without withdrawing consent, using the same
  screen.

---

## The only data that leaves your phone

Two things, and only these two:

### 1. UK postcode lookup

If you type a **UK postcode** into the search box, StopSnoozer sends that
postcode to **postcodes.io**, a free public postcode API, to convert it into
coordinates. This happens only when you type a postcode, only at the moment you
search, and the postcode is not stored by StopSnoozer afterwards.

We do not control postcodes.io. Its own privacy practices are documented at
<https://postcodes.io>. If you do not want to use it, search by stop or station
name instead — that search runs entirely against the offline database bundled
with the app and makes no network request.

### 2. Nothing else

There is no analytics SDK, no advertising SDK, no crash-reporting SDK, and no
account system in this version of StopSnoozer. Transport data (stop locations,
route topology, platform depths, run times) is downloaded once when the app is
*built*, from Transport for London and the Department for Transport's NaPTAN
dataset, and bundled into the app. Your device does not contact those services
during use.

If crash reporting is added in a future version, this policy will be updated
before that version is released, and the Google Play Data Safety section will be
updated to match.

---

## Data stored on your device

StopSnoozer keeps the following on your phone, in its private app storage:

- Your saved stops, alarms and trip groups
- Your app settings and theme
- The offline UK stop database bundled with the app
- Learned Wi-Fi/cell identifiers, if you consented to that

Uninstalling StopSnoozer deletes all of it. There is no cloud copy, which also
means a new phone starts from scratch.

### Sensor logging (field-test builds)

Development builds include an opt-in "Record sensor data for this journey"
switch, used to calibrate the detection engine. It is off by default, writes to
the app's own storage, and the resulting files contain sensor readings and stop
identifiers only — no name, no account, no contact details. Public release
builds do not enable it by default.

---

## Permissions StopSnoozer requests, and why

| Permission | Why |
|---|---|
| Precise location | Detecting arrival at above-ground stops |
| Background location ("Allow all the time") | Firing the alarm when the app is closed or the screen is off — the core function |
| Notifications | Showing the alarm and the tracking notification |
| Exact alarms / full-screen intent | Firing the alarm at the right moment and showing it over the lock screen. Android grants these automatically to apps whose core function is alarms |
| Ignore battery optimisations | Optional. Stops the system killing tracking mid-journey |
| Wi-Fi state / phone state | Optional, consent-gated. Reading nearby network identifiers as described above |
| Activity recognition | Confirming you are in a vehicle |
| Internet | Postcode lookup only |

---

## Your rights

Because StopSnoozer holds no data about you on any server, most data-protection
requests resolve on your own device:

- **Access / portability** — the data is in the app on your phone.
- **Erasure** — use the erase control in System Health, or uninstall the app.
- **Withdraw consent** — System Health → Privacy & Learned Data.

If you believe your data protection rights have been infringed, you may complain
to the UK Information Commissioner's Office at <https://ico.org.uk>.

---

## Children

StopSnoozer is not directed at children and does not knowingly collect data from
anyone under 13.

---

## Changes to this policy

Material changes will be reflected here with an updated "Last updated" date, and
the Google Play Data Safety declaration will be kept consistent with this page.

---

## Contact

**patelparthm2000@gmail.com**

---

*Contains public sector information licensed under the Open Government Licence
v3.0. Powered in part by TfL Open Data. Contains OS data © Crown copyright and
database right 2026.*
