
# Shinden Mobile

Hobby project that allows you to watch content from shinden.pl in mobile app.

App was made for my own purposes.
The project is far from perfect, but it should be usable.

## Status => W.I.P

App was made in mind of smartphone devices. 

Even though most functions **should** work, I don't guarantee they **will** work properly on your device.

## Description

Flutter shows webview with shinden webpage, injects css and js files to change how page looks and add / fix some functionalities. 

App allows you to watch videos from multiple providers (in highest available quality) in external video players.

The app injects js that allows the extraction of a direct link to the video. In some cases app intercept requests to extract direct link.

## What's inside

- Pure Dark Mode
- Heavily slimmed down UI
- Lot's of UI changes / fixes
- AdBlock
- New Watch List
- App Link - open shinden link in app rather than in browser (enable in system settings first)
- Stream to external video player (VLC, Mx Player etc) or download videos
    - app handles some video providers like cda, gdrive, mp4upload, sibnet...
    - more to come (maybe)

## Screenshots

<table>
    <tr>
        <td align="center">
            <img src="/screenshots/s1.png" width="45%">
            <img src="/screenshots/s2.png" width="45%">
            <img src="/screenshots/s3.png" width="45%">
            <img src="/screenshots/s4.png" width="45%">
        </td>
    </tr>
</table>


## Download

[Releases](https://github.com/SerpentDash/shinden_mobile/releases)
