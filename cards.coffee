crypto = require 'crypto'
_ = require 'underscore'
term = require( 'terminal-kit' ).terminal
delay = require 'delay'


do ->
	
	values = [1..13]
	suits = [0..3]

	gameTally =
		played: 0
		winnable: 0

	boards = {}
	cycleCardsStack = 0



	suitNames =
		0: 'H'
		1: 'D'
		2: 'C'
		3: 'S'

	class Card

		suit: 0
		value: 0

	createDeck = ->

		deck = []
		_.each values, (v) ->
			_.each suits, (s) ->
				card = new Card()
				card.suit = s
				card.value = v
				deck.push card
		return deck


	deck = createDeck()


	blankArray = (array) ->
		for i in [0..array.length-1]
			array[i] = []

	# create a blank game board
	createBoard = ->
		board =
			goals : blankArray [1..4]
			cells: blankArray [1..4]
			stacks: blankArray [1..10]
			

	cardName = (card) ->
		return '   ' unless card?
		v = card.value
		v = 'A' if v is 1
		v = 'J' if v is 11
		v = 'Q' if v is 12
		v = 'K' if v is 13
		v = "#{v}#{suitNames[card.suit]}"
		while v.length  < 3
			v = " #{v}" 
		return v


	printBoard = (board)  ->

		colorize = (card) -> 
			return unless card?
			term.red() if card.suit is 0
			term.brightRed() if card.suit is 1
			term.blue() if card.suit is 2
			term.brightBlue() if card.suit is 3

		
		for i in [0...4]
			term.moveTo(1+(i*4),1)
			colorize(_.last(board.goals[i]))
			term(cardName(_.last(board.goals[i])))

		for i in [0...4] 
			term.moveTo(30+(i*4),1)
			colorize(board.cells[i][0])
			term(cardName(board.cells[i][0]))

		maxLength = _.chain(board.stacks)
		.map (s) -> s.length
		.max()
		.value()

		for r in [0...maxLength+5]
			for c in [0...10]
				term.moveTo(1+(c*4),3+r)
				card = board.stacks[c][r]
				colorize(board.stacks[c][r])
				term(cardName(board.stacks[c][r]))


		term.defaultColor()
		term.moveTo(50,2,"Games Played #{gameTally.played}")
		term.moveTo(50,4,"Winnable Games #{gameTally.winnable}")
		term.moveTo(50,6,"Total Configurations: #{_.keys(boards).length}")
		term.moveTo(50,8,"Stack Size: #{cycleCardsStack}")
		
		
			





	# lay the deck out on the board
	initializeGame = () ->
		deck = createDeck()
		deck = _.shuffle deck

		board = createBoard()


		_.each board.stacks, (stack) ->
			_.each [1..5], ->
				stack.push deck.pop()

		# that's 50 cards.  Do the remain 2 into the free cells
		board.cells[1].push deck.pop()
		board.cells[2].push deck.pop()


		boards = {}
		addBoard(board)

		return board


	# you cannot create a sequence of more than 5 consequetive cards if a lower card of the same suit is higher in the stack.
	# Doing so will block that suit from ever making it to the goal, because you can only move 5 cards in sequence at once
	# we can ensure this doesn't happen and reduce our possiblity tree
	notBlockingMove = (card,target) ->
		# assume that card is legal to land on target.

		count = 1 # we are going to count the sequence
		foundLower = false

		stack = [].concat(target).reverse()
		stack = stack[1..] # we don't need to check this first one, since we know its going to be same suit with card value -1

		currentCard = _.last(target)
		_.each stack,(c) ->
			if currentCard? and c.suit is currentCard.suit and c.value is (currentCard.value+1)
				count++
				currentCard = c
			else
				currentCard = undefined

			if currentCard is undefined
				foundLower = true if c.suit is card.suit and c.value < card.value

		return true unless foundLower
		return false




	# determine if legal move
	# target is the 'stack' destination
	# target type is 'goal', 'cell', or 'stack'
	isLegalMove = (card,target,targetType) ->


		if targetType is 'goal'
			return true if target.length is 0 and card.value is 1 # ace on blank target
			return false if target.length is 0 and card.value isnt 1
			return true if _.last(target).suit is card.suit and _.last(target).value is (card.value-1) # same suit on previous value

		if targetType is 'cell'
			return true if target.length is 0  # can move anything so long as blank

		if targetType is 'stack'
			return true if target.length is 0 and card.value is 13 # king on blank target
			return false if target.length is 0 and card.value isnt 13 # can't move anything but king on empty stack
			return true if _.last(target).suit is card.suit and _.last(target).value is (card.value+1) and notBlockingMove(card,target)# same suit on next value

		return false


	# return all legal moves for card as an array.  Array contains target and targetType
	findLegalMoves = (source,sourceType,board) ->


		moves = []

		card = _.last source # source is a stack, so this gets the top of the stack

		return moves unless card?  # no card, no moves

		# start with goals.  We short-circuit here since a legal move to a goal doesn't require any additional sets of goals
		lm = _.find board.goals,(target) ->
			isLegalMove(card,target,'goal')
		if lm?
			moves.push
				target: lm
				targetType: 'goal'
			return moves

		# next do stacks
		_.each board.stacks,(target) ->
			if isLegalMove(card,target,'stack')
				moves.push
					target: target
					targetType: 'stack'

		# and then cells
		return moves if sourceType is 'cell' # no reason to move cell-to-cell, so short-circuit here if source and target are cells

		for target in board.cells
			if isLegalMove(card,target,'cell')
				moves.push
					target: target
					targetType: 'cell'
				break # we don't need more than on move to a cell.  One is as good as another, so break here


		return moves


	moveCard = (board,source,target) ->
		c = source.pop()
		target.push c

		printBoard(board) 

	countGoal = (board) ->
		tot = _.reduce board.goals,(memo,g) ->
			g.length + memo
		, 0
		return tot

	# returns true if the board registers as complete.  That is, all goals are occupied by 52 cards
	isSuccess = (board) ->
		tot = countGoal(board)
		return true if tot is 52
		return false


	# create a unique checksum for the boards current state. This is used to ensure we never repeat a configuration, as its
	# easy in this game to achieve the same configuration from multiple move possibilities
	# Goal configuration is not considered
	# Cells are sorted to ensure that any order of the same cards in the cells are considered to be the same configuration
	checksumBoard = (board) ->
		cells = _.chain(board.cells)
		.map (c) -> if c[0]? then c[0].suit * 100 + c[0].value else 0
		.sortBy()
		.value()

		# Sort the stacks by the first card.  The order of the stacks doesn't matter, only what's in them.  By sorting them, we'll ensure that any original order is considered to be the same
		stacks = _.sortBy board.stacks,(s) ->
			return s[0].suit * 100 + s[0].value if s[0]? 
			return 0

		str = JSON.stringify
			s: stacks
			c: cells


		return crypto.createHash('md5').update(str).digest('base64')




	# add board to our list of completed boards, but only if its not a repeat.  return true if repeat
	addBoard = (board) ->
		chksum = checksumBoard(board)
		f = boards[chksum]

		boards[chksum] = true unless f?
		

		if not f? and len % 1000 is 0
			len = _.keys(boards).length
		

		return true if f?
		return false

	removeBoard = (board) ->
		delete boards[board.checksum]



	# given a list of legal moves for a given card ( source ), make each legal move
	# That is, we will make that move, then follow that line of the possibility tree recursively.  If that line is not successful, we move to the next legal move
	cycleThroughLegalMoves = (board,source,legalMoves) ->
		return false if legalMoves.length is 0 # no moves, return false ( not successful )

		moveIndex = -1

		while moveIndex < legalMoves.length-1
			moveIndex++

			# no point in moving a single king on a stack to an empty stack. Since a king's only legal move in the stack is to an empty cell, we have some simple logic
			continue if source.length is 1 and source[0].value is 13 and legalMoves[moveIndex].targetType is 'stack'

			moveCard(board,source, legalMoves[moveIndex].target) # actually mode the card
			return true if isSuccess(board) # check for success

			repeat = addBoard(board)

			unless repeat # don't continue unless move wasn't a repeat ( classic example of too many negatives:  continue if not repeated)
				success = cycleThroughCards board
				return true if success

			moveCard board,legalMoves[moveIndex].target,source   # put the card back



		return false


	

	cycleThroughCards = (board) ->


		# there are 14 moveable stacks, 10 on the bottom, 4 cells on top
		source = (index) ->
			if index < 10
				r =
					stack: board.stacks[index]
					sourceType: 'stack'
			else
				r =
					stack: board.cells[index-10]
					sourceType: 'cell'
			return r


		cycleCardsStack++

		cardIndex = 0

		# quick scan for goal moves.  This just checkes to see if any of the stacks for cells can legally move to a goal
		legalMoves = undefined
		s = undefined
		for i in [0..13]
			s = source(i)
			legalMoves = findLegalMoves s.stack,s.sourceType,board
			break if legalMoves?[0]?.targetType is 'goal'
			s = undefined

		if s? # we have a card we can move to goal
			return cycleThroughLegalMoves(board,s.stack,legalMoves)

		else

			while cardIndex < 14

				s = source(cardIndex)
				legalMoves = findLegalMoves s.stack,s.sourceType, board
				success = cycleThroughLegalMoves board, s.stack, legalMoves

				return true if success

				cardIndex++

			cycleCardsStack--
			return false


	playGame = ->


		board = initializeGame()

		printBoard(board)


		success = cycleThroughCards(board,0)

		return success




	for i in [1..10]
		term.clear()
		success = playGame()
		gameTally.played++
		gameTally.winnable++ if success

	term.clear()
	console.log gameTally

	console.log 'done'
