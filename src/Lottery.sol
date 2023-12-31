//SPDX-License-Indentifier:MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title A simple lottery contract
 * @author Stefania
 * @dev implements chainlink VRF V2 and chainlink automation
 *  Layout of contracts: ErTS, EvMF
 *      ErTS -> errors, types, state variables
 *      EvMF -> events, modifiers, functions
 */
contract Lottery is VRFConsumerBaseV2 {
    error Lottery__EthValueBelowTicketPrice__error();
    error Lottry__TransferToWinnerFailed__error();
    error Lottery__ClosedState__error();
    error Lottery__UpkeepNotNeeded__error(
        uint256 balance,
        uint256 numPlayers,
        uint256 lotteryState
    );

    enum LotteryState {
        OPEN, //0
        CLOSE //1
    }

    uint16 private REQUEST_CONFIRMATIONS = 2;
    uint32 private NUM_WORDS = 1;

    uint256 private immutable i_lotteryDuration;
    uint256 private immutable i_ticketPrice;
    VRFCoordinatorV2Interface private immutable i_VRFCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimestampSnapshot; //always a smaller number than block.timestamp
    address private s_lastWinner;
    LotteryState private s_currentLotteryState;

    event Lottery__PlayerAccepted__event(address indexed player);
    event Lottery__LotteryReset__event();
    event Lottery__WinnerRequested__event(uint256 indexed requestId);
    event Lottery__WinnerChosen__event(address indexed winner);

    constructor(
        uint256 _ticketPrice,
        uint256 _lotteryDuration,
        address _VRFCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_VRFCoordinator) {
        i_ticketPrice = _ticketPrice;
        i_lotteryDuration = _lotteryDuration;
        s_lastTimestampSnapshot = block.timestamp;
        i_VRFCoordinator = VRFCoordinatorV2Interface(_VRFCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
        s_currentLotteryState = LotteryState.OPEN;
    }

    function buyTicket() external payable {
        if (msg.value < i_ticketPrice) {
            revert Lottery__EthValueBelowTicketPrice__error();
        }
        if (s_currentLotteryState == LotteryState.CLOSE) {
            revert Lottery__ClosedState__error();
        }
        s_players.push(payable(msg.sender));
        emit Lottery__PlayerAccepted__event(msg.sender);
    }

    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded__error(
                address(this).balance,
                s_players.length,
                uint256(s_currentLotteryState)
            );
        }
        s_currentLotteryState = LotteryState.CLOSE;
        uint256 requestId = i_VRFCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit Lottery__WinnerRequested__event(requestId);
    }

    /**
     * @dev Chainlink node (VRF coordinator) will call this function to give back the randomWords
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        //checks -none
        //effect
        uint256 _winnerIndex = randomWords[0] % s_players.length;
        address payable _winnerAddress = s_players[_winnerIndex];
        s_lastWinner = _winnerAddress;
        emit Lottery__WinnerChosen__event(_winnerAddress);
        s_currentLotteryState = LotteryState.OPEN;
        s_lastTimestampSnapshot = block.timestamp; //restart the clock over
        s_players = new address payable[](0);
        emit Lottery__LotteryReset__event();
        //interaction
        (bool success, ) = _winnerAddress.call{value: address(this).balance}(
            ""
        );
        if (!success) {
            revert Lottry__TransferToWinnerFailed__error();
        }
    }

    function checkUpKeep(
        bytes memory /*checkdata*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool lotteryDurationPassed = (block.timestamp -
            s_lastTimestampSnapshot) >= i_lotteryDuration;
        bool lotteryHasPlayers = s_players.length > 0;
        bool lotteryIsInOpenState = s_currentLotteryState == LotteryState.OPEN;
        bool lotteryHasBalance = address(this).balance > 0;
        upkeepNeeded = (lotteryDurationPassed &&
            lotteryHasPlayers &&
            lotteryIsInOpenState &&
            lotteryHasBalance);

        // not needed -> return (upkeepNeeded, "0x0");
    }

    // Getters
    function getTicketPrice() external view returns (uint256) {
        return i_ticketPrice;
    }

    function getLotteryDuration() external view returns (uint256) {
        return i_lotteryDuration;
    }

    function getLastWinner() external view returns (address) {
        return s_lastWinner;
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_currentLotteryState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }
}
