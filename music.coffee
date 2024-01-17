
_ = require 'underscore'
async = require 'async'
clone = require 'clone'


BEAT_MAP =
	'S' : .25
	'E' : 0.5
	'Q' : 1
	'H' : 2
	'W' : 4

testScore =
	'Piano': [
		'C5.Q', 'D5.W', 'E5.H', 'F5.S','G5.E'
	]
	'Sax': [
		'C5.E','D5.S','C5.S','G5.Q','G5.Q','G5.Q','G5.Q'
	]
	'Clarinet': [
		'C5.Q','D5.QD','D5.Q','D5.QD'
	]



class ScorePlayer

	voiceTracker : {}


	constructor: (score,@bpm) ->
		@score = clone score
		@bpm ?= 90
		@msPerBeat = 1 / (@bpm / (60*1000))

		_.each _.keys(score),(voice) =>
			@voiceTracker[voice] =
				index: 0
				elapsed: 0
				complete: false


		@parseScore()
		console.log @score

	parseScore : =>
		_.each @score,(notes,voice) =>
			@score[voice] = _.map (notes), (note) =>
				parts = note.split('.')
				d = BEAT_MAP[parts[1][0]] * @msPerBeat
				if parts[1][1] is 'D' # dotted
					d += (d * 0.5)
				result =
					pitch: parts[0]
					duration: d



	playNote: (voice,pitch) ->
		console.log "#{voice}: #{pitch}"


	tick : (timeElapsed) =>

		_.each @voiceTracker,(info,voice) =>
			return if info.complete
			note = @score[voice][info.index]
			delta = (timeElapsed+info.elapsed) - note.duration
			if delta > 0
				# find next note and play it
				info.index++
				for i in [info.index...@score[voice].length]
					info.index = i
					break if delta < @score[voice][i].duration
					delta -= @score[voice][i].duration

				if info.index < @score[voice].length
					info.elapsed = delta
					note = @score[voice][info.index]
					@playNote voice,note.pitch
				else
					info.complete = true

			else
				info.elapsed += timeElapsed

	play: (cb) =>

		markTime = (new Date()).getTime()
		# initialize notes
		_.each @score,(notes,voice) =>
			@playNote voice,notes[0].pitch


		ticky = =>
			elapsed = (new Date()).getTime() - markTime
			@tick elapsed
			incomplete = _.find @voiceTracker, (info) -> info.complete is false
			return cb?() unless incomplete?
			markTime = (new Date()).getTime()
			setTimeout ticky,20

		setTimeout ticky,20



# Main Function
if process.argv[1] and process.argv[1].match(__filename)
	sp = new ScorePlayer(testScore,200)
	sp.play ->
		console.log 'done'
