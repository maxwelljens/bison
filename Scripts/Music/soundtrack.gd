class_name Soundtrack
extends Resource
## A reusable playlist handed to the [code]Music[/code] autoload.
##
## Saved as a [code].tres[/code] (e.g. [code]Audio/Music/sets/gameplay.tres[/code])
## so every scene that plays the same score shares one asset instead of
## duplicating stream references. A scene announces its soundtrack with
## a [MusicCue] child node; this resource is only data.

@export_category("Tracks")
## The score, in rotation order.
@export var tracks: Array[AudioStream] = []

@export_category("Loop")
## Gapless decoder loop instead of a crossfade restart - for
## single-track sets such as a title theme. With more than one track
## the rotation would never advance, so [code]Music[/code] warns and
## ignores the flag.
@export var loop: bool = false
