###
Seahaven Towers Solver

( https://en.wikipedia.org/wiki/Seahaven_Towers )

In short:  Goal is to build up goal stacks from Ace to King in same suit
	- There are 4 goal stacks, one for each suit.  Goals stacks start empty, and must be filled in order from Ace to King following the same suit
	- There are 4 free cells.  Any one card may be moved to a free cell.  Cards in free cells can be moved to goal stacks for tableau stacks as per the rules of those stacks.  Initially, there are 2 free cells occupied by cards
	- 10 tableu stacks with 5 cards each.  The top-most card on the stack may be moved to a free cell, the goal if possible, or onto another tablue stack where the top-most card is of the same suit and exactly one higher in value. 
	(e.g. A 5 of Hearts may only be placed on a 6 of hearts)
	- Only Kings can be placed on empty tablue stacks.

	An ordered set of cards in a tableau stack are ones where the top most cards are ordered with respect to the card directly beneath them.  ( e.g. 5H - 4H - 3H , with 3H being the top most card).  An ordered set may be moved
	in total to another stack that continues the ordering if there are less-or-equal number of cards in the ordered set than the number of currently free cells + 1.
	Example, 5H-4H-3H may be moved on top of a 6H by moving the 3H and 4H to free cells, then moving the 5H, then moving the 4H and 3H back to the ordered set.  
	This also means that the largest ordered set that can be moved at once is 5 cards.

	This solver finds and moves these ordered sets as extents.

	6 cards in an ordered set with a lower valued card in the same suit lower in the stack is a dead-end, as there will be no way to subseuqently extract the lower valued card.  This is a blocking move that is checked and avoided.

	There are many ways to arrive at the same configuration of cards on the boards.  To avoid this while solving, each board configuration's signature is stored in a hash.  Duplicate board detection results in that path for a solution
	being abandoned. 

###

crypto = require 'crypto'
_ = require 'underscore'
term = require( 'terminal-kit' ).terminal
delay = require 'delay'


ABANDON_THRESHOLD  = 200000 # number of unique board configuration for any one game before we give up.  
# NOTE: for reasons that have been hard to pin down, the current process can result in a very broad possibility tree.  We have several checks
# to cutoff branches along the depth of a tree, but when the tree is very wide, the number of unique configurations goes towards a million before we
# determine success or failure.  As this can get very slow, we just abandon these games.


do ->
	
	values = [1..13]
	suits = [0..3]
	gameMoves = []
	totalMoves = 0

	gameTally =
		played: 0
		winnable: 0
		losers: 0
		abandoned: 0

	boards = {}
	totalConfigurations = 0
	stackConfigurations = {}

	cycleCardsStack = 0

	repeatsAvoided = 0
	


	suitNames =
		0: 'H'
		1: 'D'
		2: 'C'
		3: 'S'

	class Card

		suit: 0
		value: 0

	# lay the deck out on the board
	initializeGame = () ->
		deck = createDeck()
		deck = _.shuffle deck		

		board = createBoard()


		for stack in board.stacks
			for i in [1..5]
				stack.push deck.pop()

		# that's 50 cards.  Do the remain 2 into the free cells
		board.cells[1].push deck.pop()
		board.cells[2].push deck.pop()


		boards = {} # saved configurations.  ( Used to check for repeated boards)
		totalConfigurations = 0 # number of boards saved
		gameMoves = [] # the array of game moves to the conclusion.  This array will grow or contract depending if we are advancing or retreating on the possibility tree
		cycleCardsStack = 0 # just a counter to keep track of the depth into the possibility tree
		totalMoves = 0 # The total number of times we've moded cards
		repeatsAvoided = 0 # The total number of times we've encountered a repeat board configuration
		
	
		addBoard(board) # record the initial configuration
		

		return board


	# initialize a deck of 52 cards
	createDeck = ->

		deck = []
		for s in suits
			for v in values
				card = new Card()
				card.suit = s
				card.value = v
				deck.push card
		return deck


	blankArray = (array) ->
		for i in [0..array.length-1]
			array[i] = []

	# create a blank game board.  The board consist of goal stacks, cell stacks and the tableau stacks.  ( Note: cells stacks will have only zero or one card in them. )
	createBoard = ->
		board =
			goals : blankArray [1..4]
			cells: blankArray [1..4]
			stacks: blankArray [1..10]
			

	# For output, the name of the card from its value
	cardName = (card,placeHolder='   ') ->
		return placeHolder unless card?
		v = card.value
		v = 'A' if v is 1
		v = 'J' if v is 11
		v = 'Q' if v is 12
		v = 'K' if v is 13
		v = "#{v}#{suitNames[card.suit]}"
		while v.length  < 3
			v = " #{v}" 
		return v

	# pretty output of a stack, for debug purposes
	stackStr = (stack) -> 
		return 'x' if stack.length is 0
		str = '- '
		for c in stack
			str += cardName(c)
		str += ' = '
		return str

	# nice, pretty, terminal friendly output of the current state of affairs
	printBoard = (board,title='')  ->

		offsetY = 2
		term.moveTo(1,1).eraseLine()
		term(title)

		colorize = (card) -> 
			return unless card?
			term.red() if card.suit is 0
			term.brightRed() if card.suit is 1
			term.blue() if card.suit is 2
			term.brightBlue() if card.suit is 3

		
		for i in [0...4]
			term.moveTo(1+(i*4),offsetY+1)
			colorize(_.last(board.goals[i]))
			term(cardName(_.last(board.goals[i]),' - '))

		for i in [0...4] 
			term.moveTo(30+(i*4),offsetY+1)
			colorize(board.cells[i][0])
			term(cardName(board.cells[i][0],' x '))

		maxLength = _.chain(board.stacks)
		.map (s) -> s.length
		.max()
		.value()

		for r in [0...maxLength+5]
			for c in [0...10]
				term.moveTo(1+(c*4),offsetY+3+r)
				card = board.stacks[c][r]
				colorize(board.stacks[c][r])
				term(cardName(board.stacks[c][r]))


		term.defaultColor()
		term.moveTo(50,offsetY+2,"Games Played #{gameTally.played}")
		term.moveTo(50,offsetY+4,"Winnable: #{gameTally.winnable}  Losers: #{gameTally.losers}   Abandoned: #{gameTally.abandoned}")
		term.moveTo(50,offsetY+6,"Call Stack Size: #{cycleCardsStack}      ")
		term.moveTo(50,offsetY+8,"Total Moves: #{gameMoves.length}      ")
		term.moveTo(50,offsetY+10,"Total Configurations: #{totalConfigurations}  Repeats Found: #{repeatsAvoided}   ")





	# you cannot create a sequence of more than 5 consecutive cards if a lower card of the same suit is higher in the stack.
	# Doing so will block that suit from ever making it to the goal, because you can only move 5 cards in sequence at once
	# e.g. with stack 2H 10H 9H 8H 7H 6H, moving the 5H on the end would cause a situation where the 2H could never be freed.
	# we can ensure this doesn't happen and reduce our possiblity tree
	isBlockingMove = (card,target,extentLength) ->
		# assume that card is legal to land on target.
		return false if target.length < 5 # impossible to have a block unless there are at least 5 cards ( the 6th card added would be the blocking move)

		foundLower = false
		count = 1

		r = [].concat(target).reverse() # reverse the stack for easy iteration ( top of the stack is first in array )
		currentCard = r[0]
				
		for c in r[1..]
			# current card will be defined as long the card (c) in the iteration is the same suit and one greater in value
			if currentCard? and c.suit is currentCard.suit and c.value is (currentCard.value+1)
				currentCard = c # set current card to iteration card
				count++
			else
				currentCard = undefined

			# If we find card that is same suit and lower value than the card we are adding, we break with a flag
			
			if c.suit is card.suit and c.value < card.value
				foundLower = true
				break
		
		return true if foundLower and (count+extentLength) >= 5
		return false

	# returns how many cards on the top of the stack are ordered ( inclusive ).  That is, there will always be at least one, unless the stack is empty
	stackOrderedCount = (stack) ->
		return 0 if stack.length is 0
		r = [].concat(stack).reverse()
		count = 1
		for i in [1...r.length]
			break unless r[i-1].suit is r[i].suit and r[i-1].value is r[i].value-1
			count++
		return count

	isDisconnectedStack = (stack) ->
		return flase if stack.length <= 1
		r = [].concat(stack).reverse()
		breakPoint = false
		isDisconnected = false
		suit = r[0].suit
		for i in [1...r.length]
			if suit is r[i].suit 
				continue unless breakPoint
				isDisconnected = true
			breakPoint = true
			

		return isDisconnected



	# Check to see if the stack is fully ordered
	# a stack is considered to be fully ordered if any ordered sequence from the top of the stack down is made up of more than the available free cells + 1
	# ( once you've hit 6 cards, the only place you can move the top card is to the goal.  You'll fill up the available cells trying to move the whole sequence)
	isFullyOrdered = (board,stack) ->
		return true if stack.length is 0				
		freeCells = countFreeCells(board)
		

		return false unless stack.length > (freeCells+1) # impossible to be fully ordered unless stack size is greater than the available free cells + 1

		count = stackOrderedCount(stack)

		return true if count > (freeCells+1)

		return false



	# determine if moving the card to the target stack constitues a legal move
	# target is the 'stack' destination
	# target type is 'goal', 'cell', or 'stack'
	isLegalMove = (card,target,targetType,extentLength) ->
		extentLength ?= 1
		# logic for target being goal
		if targetType is 'goal'
			# two conditions.  The card is an Ace, and the goal is empty
			# -or- the target's card is the same suit, and exactly one less in card value
			if target.length is 0
				return true if card.value is 1 # ace on blank target
				return false 

			return ( _.last(target).suit is card.suit and _.last(target).value is (card.value-1) ) # same suit on previous value

		# logic for target being cell
		if targetType is 'cell'
			return (target.length is 0)  # can move anything so long as blank

		# target is stack
		if target.length is 0
			return true if card.value is 13 # king on blank target
			return false # can't move anything but king on empty stack
		return true if _.last(target).suit is card.suit and _.last(target).value is (card.value+1) and not isBlockingMove(card,target,extentLength) # same suit on next value.  Blocking moves are not allowed.  ( see isBlockingMove )

		return false


	# return all legal moves for a stack.  ( usually the last (top) card of a stack, and sometimes and extent of cards)
	findLegalMoves = (source,sourceType,board) ->
		moves = []

		card = _.last(source) # source is a stack, so this gets the top of the stack

		return moves unless card?  # no card, no moves
		
		# first check, for each goal stack, if move to goal is a legal move
		for target in board.goals 
			continue unless isLegalMove(card,target,'goal')		
			moves.push
				target: target
				targetType: 'goal'
			return moves # We short-circuit here since a legal move to a goal doesn't require any additional examination of moves.  We just always move to the goal

        # short-circuit here if source stack is fully ordered.  
		return moves if sourceType is 'stack' and isFullyOrdered(board,source) # no reason to move fully ordered card except to goal ( see isFullyOrdered for full definition )

		# next do stacks		
		toStackCard = card # our card might be different if we are in a stack extent
		extent = 0

		if sourceType is 'stack'
			# stack to stack moves will be using an extent
			extent = findExtent(board,source)  # find the extent value
			if extent > 0
				toStackCard = source[-extent..][0] # our card to check legal move is the bottom most card in the extent.  e.g, in an extent with value 5,3,2 , the card to compare for legal move is 5

		for target in board.stacks
			if isLegalMove(toStackCard,target,'stack',extent)
				moves.push
					target: target
					targetType: 'stack'
					extent: extent
				return moves # there is only one possible move for each card in a stack to another portion of a stack.   In the case of kings, one empty stack is as good as another. 

		# and then cells
		return moves if sourceType is 'cell' # a card in a cell should only move to a goal or stack, which have already been considered.  Short-circuit here if our card is in a cell
		return moves if sourceType is 'stack' and stackOrderedCount(source) > 1 # we do not move stack card to a cell if its ordered in any way.  ( The extent mechanism will capture stack to stack moves )

		for target in board.cells
			if isLegalMove(card,target,'cell')
				moves.push
					target: target
					targetType: 'cell'
				return moves # we don't need more than on move to a cell.  One is as good as another, so break here


		return moves

	# an extent is a ordered set of cards ( starting with top most ) that is less or euqal to the number of freeCells+1
	# For example, the most basic extent is 1 card, and we don't need any free cells
	# we can move an extent of values 5,4,3 if there are 2 or more free cells
	# logic is simple:  move every card except the final one into the available free cells, move the final card to target, then move cards from cells back onto final card in new position
	# we will return the total number of cards in the extent, or 0 meaning there is no movable card
	findExtent = (board,stack) ->
		freeCellCount = countFreeCells(board)
		r = [].concat(stack).reverse()
		count = 1
		for i in [1...r.length]
			break unless r[i-1].suit is r[i].suit and r[i-1].value is r[i].value-1
			count++

			
		return count if count <= (freeCellCount+1)

		return 0
		



	# We move an extent by moving extent-1 cards to free cells, moving the inner most card in the extent, then moving the remaining from the cells in reverse order
	# e.g. if we have an extent of values 5,4,3 moving to a target stack where top card is 6, move 3, 4 to free cells, move 5 -> target stack, then 4,3 to target stack in that order
	# this totals to (extent-1) * 2 + 1 total moves.  This amount should be used when undoing this action
	# assume there are enough free cells to do this
	moveExtent = (board,source,target,extent) ->
		freeCells = findFreeCells(board)
		for i in [0...extent-1]
			moveCard(board,source.stack,source.sourceType,freeCells[i],'cell',"Move Extent #{extent}",true)

		moveCard(board,source.stack,source.sourceType,target.target,'stack',"Move Extent #{extent}",true)
		for i in [(extent-1)...0]
			moveCard(board,freeCells[i-1],'cell',target.target,target.targetType,"Move Extent #{extent}",true)

		return


	moveCard = (board,source,sourceType,target,targetType,msg,extent) ->
		totalMoves++

		c = _.last(source)

		msg ?= "Move: "
		msg += "#{cardName(c)} From: "
		msg += stackStr(source)
		msg += "(#{sourceType}) "
		msg += "To: "
		msg += stackStr(target)
		msg += "(#{targetType}) "

		gameMoves.push 
			source: source
			sourceType: sourceType
			target: target
			targetType: targetType
			msg: msg
			extent: extent

		c = source.pop()
		target.push c
			
		printBoard(board,"Moving #{msg}")  if totalMoves % 5000 is 0

	undoLastMove = (board) ->
		move = gameMoves.pop()
		c = move.target.pop()
		move.source.push(c)

	countGoal = (board) ->
		tot = _.reduce board.goals,(memo,g) ->
			g.length + memo
		, 0
		return tot

	findFreeCells = (board) ->
		return _.filter board.cells,(c) -> c.length is 0

	countFreeCells = (board) ->
		cells = findFreeCells(board)
		return cells.length
		

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

		cells = JSON.stringify(cells)
		stacks = JSON.stringify(stacks)

		return crypto.createHash('md5').update(cells).update(stacks).digest('base64')


	# add board to our list of completed boards, but only if its not a repeat.  return true if repeat
	addBoard = (board) ->
		chksum = checksumBoard(board)
		f = boards[chksum]

		unless f?
			boards[chksum] = true 
			totalConfigurations++

		repeatsAvoided++ if f?
	
		return true if f?
		if totalConfigurations > ABANDON_THRESHOLD # give up after a certain point
			board.abandoned = true
			return true
		return false


	checksumStack = (stack) ->
		str = JSON.stringify stack
		return crypto.createHash('md5').update(str).digest('base64')


	# given a list of legal moves for a given card ( source ), make each legal move
	# That is, we will make that move, then follow that line of the possibility tree recursively.  If that line is not successful, we move to the next legal move
	cycleThroughLegalMoves = (board,source,legalMoves) ->
		return false if legalMoves.length is 0 # no moves, return false ( not successful )

		for moveIndex in [0...legalMoves.length]
			lm = legalMoves[moveIndex]
			extent = 0
			if source.sourceType is 'stack' and lm.targetType is 'stack'
				extent = lm.extent # see findLegalMoves() for more on extent
				return false if extent is 0
				moveExtent(board,source,lm,extent) # move the extent instead of single card if extent is found
			else
				moveCard(board,source.stack,source.sourceType, lm.target,lm.targetType) # actually move the card
			return true if isSuccess(board) # check for success

			
			repeatBoard = addBoard(board)
			

			unless repeatBoard  # don't continue unless move wasn't a repeat ( classic example of too many negatives:  continue if not repeated)
				success = cycleThroughCards(board) # recursively attempt to solve the new board configuration
				return true if success

			
			if extent > 0
				totalExtentMoves = (extent-1)*2 + 1  # each extent move is recorded as individual moves, so we need to back them all out individually
				undoLastMove(board) for i in [1..totalExtentMoves]
			else
				undoLastMove(board)



		return false


	

	cycleThroughCards = (board) ->


		# there are 14 moveable stacks, 10 on the bottom, 4 cells on top
		source = (index) ->
			if index > 3
				r =
					stack: board.stacks[index-4]
					sourceType: 'stack'
			else
				r =
					stack: board.cells[index]
					sourceType: 'cell'
			return r


		cycleCardsStack++
		success = false

		# The following is an an optimization on which moves we will consider a priorty
		# collect the legal moves for each stack or cell
		# remove all sources that have no legal moves, and sort the rest to favor moving to goal
		# in this way, we will always consider the move to goal as top priority
		allStacks = []
		for stackIndex in [0..13]

			s = source(stackIndex)
			legalMoves = findLegalMoves s.stack,s.sourceType, board
			allStacks.push 
					source: s
					legalMoves: legalMoves

		allStacks = _.chain allStacks
			.filter (s) -> s.legalMoves.length > 0
			.sortBy allStacks,(s) ->
				return 0 if s.legalMoves[0].targetType is 'goal'
				if s.legalMoves[0].targetType is 'stack'
					return 10000 if isDisconnectedStack(s.legalMoves[0].target)
				return s.legalMoves[0].target.length
				
			.value()
		
		for s in allStacks
			success = cycleThroughLegalMoves board, s.source, s.legalMoves
			break if success

		cycleCardsStack--
		return success

	replayGame = (board) ->
		# rewind the entire game based on the move stack
		moveCopy = [].concat(gameMoves) # make a copy of all the moves
		
		# undo all moves
		for i in [0...gameMoves.length]
			undoLastMove(board)
			printBoard(board,"Rewinding        ")
			await delay(1)


		count = 0
		for move in moveCopy
			count++
			moveCard(board,move.source,move.sourceType,move.target,move.targetType)
			unless move.extent
				printBoard(board,move.msg) 
				await delay(100)

		# Output all the moves made
		# for move in moveCopy
			# console.log move.msg

		return

			


	playGame = (board) ->

		printBoard(board,"Starting Game")

		success = cycleThroughCards(board,0)

		return success


	for i in [1..1000]
		term.clear()
		board = initializeGame()
		success = playGame(board)
		gameTally.played++
		gameTally.winnable++ if success
		gameTally.losers++ unless success or board.abandoned
		gameTally.abandoned++ if board.abandoned
		# await replayGame(board) if success
			


	
	term.clear()
	console.log gameTally

	console.log 'done'
