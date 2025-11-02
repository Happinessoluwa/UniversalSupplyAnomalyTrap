// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract UniversalSupplyAnomalyTrap is ITrap {
    uint256 public constant SUPPLY_DROP_THRESHOLD_BP = 500;  // 5% drop
    uint256 public constant SUPPLY_SPIKE_THRESHOLD_BP = 500; // 5% increase
    uint256 public constant BALANCE_ANOMALY_THRESHOLD_BP = 1000; // 10% deviation

    struct SupplyData {
        uint256 totalSupply;
        uint256 referenceBalance;
        uint256 ratioBP;
        bool isAnomalous;
        uint256 timestamp;
    }

    string constant MESSAGE = "Bridge or token supply anomaly detected";

    // Called periodically by Drosera to collect current state
    function collect() external view override returns (bytes memory) {
        // In a real deployment, Drosera binds this to a monitored token
        // The target contract (token) is passed in via the trap metadata (toml)
        IERC20 token = IERC20(address(this));

        uint256 total = 0;
        uint256 refBalance = 0;
        try token.totalSupply() returns (uint256 s) { total = s; } catch {}
        try token.balanceOf(address(this)) returns (uint256 b) { refBalance = b; } catch {}

        uint256 ratio = total > 0 ? (refBalance * 10_000) / total : 0;
        bool anomaly = ratio > BALANCE_ANOMALY_THRESHOLD_BP;

        return abi.encode(SupplyData({
            totalSupply: total,
            referenceBalance: refBalance,
            ratioBP: ratio,
            isAnomalous: anomaly,
            timestamp: block.timestamp
        }));
    }

    // Determines if Drosera should trigger a response
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        if (data.length == 0) return (false, bytes(""));
        SupplyData memory latest = abi.decode(data[0], (SupplyData));

        if (latest.isAnomalous) {
            return (true, abi.encode(MESSAGE, abi.encode(latest)));
        }
        return (false, bytes(""));
    }
}
