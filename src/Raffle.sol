// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample Raffle Contract
 * @author PhoenixS
 * @notice This contract is creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    //bool calculatingWinner = false; bool lotteryState = open, closed, calculating
    /** Type declarations */
    enum RaffleState {
        OPEN, //0-States can be converted to integers 0,1,2
        CALCULATING //1
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    //@dev Duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN; //Defaulting raffleState to open
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        //console.log(msg.value); - Will display on your test/delete before deploying as it will cost gas

        s_players.push(payable(msg.sender));
        //Events-Make migration easier and makes front end "indexing" easier
        emit EnteredRaffle(msg.sender);
    }

    // Will return when the winner should be picked
    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1.The time interval has passed between raffle runs
     * 2.The raffle is in the OPEN state
     * 3.The contract has ETH (aka, players)
     * 4.(Implicit) The subscription is funded with LINK
     */

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval; //1.
        bool isOpen = RaffleState.OPEN == s_raffleState; //2.
        bool hasBalance = address(this).balance > 0; //3.
        bool hasPlayers = s_players.length > 0; //3.
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // 0x0 states a blank bytes object

        // {revert();}
    }

    //1. Get a random number
    //2. Use the random number to pick a player
    //3. Be automatically called
    function performUpkeep(bytes calldata /* perform data */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        // Check to see if enough time has passed
        //if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //  revert();}

        s_raffleState = RaffleState.CALCULATING;

        //1. Request the RNG
        //2. Get the random number
        //3. Copied from Chainlink VRF docs
        /*uint256 requestId = */
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            //keyHash, //gas lane
            i_gasLane,
            //s_subscriptionId,
            i_subscriptionId,
            //requestConfirmations,
            REQUEST_CONFIRMATIONS,
            //callbackGasLimit,
            i_callbackGasLimit,
            //numWords
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    // Coding in CEI: Checks, Effects, Interactions
    // Checks: require(if->)
    // Effects (effects our own contract)
    // Interactions: (other contracts)

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        //Modulo Function
        //s_players = 10
        //rng =12
        //12 % 10 = 2 <-

        //Checks and Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN; //converts back to open after winner is chosen

        s_players = new address payable[](0); //resets lottery and players
        s_lastTimeStamp = block.timestamp; //resets the clock
        emit PickedWinner(winner);

        //Interactions- Should be last
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }

        //emit PickedWinner(winner); (Moved above-Events should come before Interactions)
    }

    /**Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
