// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UniversalSupplyAnomalyResponse {
    struct SupplyData {
        uint256 totalSupply;
        uint256 referenceBalance;
        uint256 ratioBP;
        bool isAnomalous;
        uint256 timestamp;
    }

    struct Report {
        SupplyData data;
        string message;
        uint256 id;
        address reporter;
    }

    event SupplyAnomalyAlert(address indexed reporter, uint256 ratioBP, uint256 timestamp);
    event ReportLogged(uint256 indexed id, address indexed reporter, bytes encodedData, string message);

    uint256 public nextId = 1;
    Report[] public reports;
    mapping(address => uint256[]) public userReports;

    function respond(string memory message, bytes calldata encodedData) external {
        SupplyData memory data = abi.decode(encodedData, (SupplyData));

        emit SupplyAnomalyAlert(msg.sender, data.ratioBP, data.timestamp);

        Report memory r = Report({
            data: data,
            message: message,
            id: nextId++,
            reporter: msg.sender
        });

        reports.push(r);
        userReports[msg.sender].push(r.id);

        emit ReportLogged(r.id, msg.sender, encodedData, message);
    }

    function getReportsCount() external view returns (uint256) {
        return reports.length;
    }

    function getReport(uint256 id) external view returns (Report memory) {
        require(id < reports.length, "Invalid ID");
        return reports[id];
    }
}
