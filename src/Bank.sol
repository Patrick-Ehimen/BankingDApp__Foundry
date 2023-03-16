// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/**
 * @title Bank
 * @author  Patrick Ehimen
 * @notice Decentralised Bank is a decentralised banking platform that allows users to
 * securely store and manage funds.
 */
contract Bank {
    // Struct to store Customer's details such as address and account balance
    struct CustomerDetails {
        address UserAddr;
        uint AcctBalance;
    }
    // Struct to store locked balance and unlock time for a customer
    struct LockedBalance {
        uint amount;
        uint unlockTime;
    }

    address public bank;
    uint internal customerCount;
    uint internal feesBalance;

    // Private array to store customer details
    CustomerDetails[] private customers;

    // Mapping to store password of a customer against its address
    mapping(address => bytes32) private passwords;
    // Mapping to check if a customer exist
    mapping(address => bool) private customerExist;
    // Mapping to store customer details against its address
    mapping(address => CustomerDetails) public customerDetails;
    // Mapping to store locked balances of a customer against its address
    mapping(address => LockedBalance[]) public lockedBalances;

    // Event to record withdrawal details
    event Withdrawal(uint amount, uint when);
    // Event to record lock details
    event Locked(uint amount, uint unlockTime);
    // Event to record unlock details
    event Unlocked(uint amount, uint unlockTime);

    receive() external payable {}

    fallback() external payable {}

    constructor() {
        bank = msg.sender;
    }

    // Function to create a new account
    function createAccount(string memory password) public {
        CustomerDetails storage accountCreated = customers.push();
        require(msg.sender != address(0), "You cannot use a zero address");
        require(!customerExist[msg.sender], "You already have an acoount");
        accountCreated.UserAddr = msg.sender;
        customerExist[msg.sender] = true;

        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        passwords[msg.sender] = hashedPassword;

        customerCount++;
    }

    // Function to deposit into the account
    function deposit() public payable {
        require(customerExist[msg.sender], "Account does not exist");
        require(msg.value > 0, "Deposit amount must be greater than 0");
        CustomerDetails storage accountCreated = customers.push();
        accountCreated.AcctBalance = msg.value;

        customerDetails[msg.sender].AcctBalance += msg.value;
        //customerDetails[msg.sender] = accountCreated;
    }

    function withdraw(uint amount, string memory password) public {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        require(hashedPassword == passwords[msg.sender], "Incorrect password");
        require(customerExist[msg.sender], "Account does not exist");
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(
            amount <= customerDetails[msg.sender].AcctBalance,
            "Insufficient funds"
        );
        uint availableBalance = customerDetails[msg.sender].AcctBalance;
        for (uint i = 0; i < lockedBalances[msg.sender].length; i++) {
            LockedBalance storage locked = lockedBalances[msg.sender][i];
            if (locked.unlockTime > block.timestamp) {
                availableBalance -= locked.amount;
            }
        }
        require(amount <= availableBalance, "Insufficient funds");

        uint bankFee = (amount * 5) / 1000;
        amount -= bankFee;
        feesBalance += bankFee;

        payable(msg.sender).transfer(amount);
        customerDetails[msg.sender].AcctBalance -= amount;

        emit Withdrawal(address(this).balance, block.timestamp);
    }

    function withdrawFees() public {
        require(msg.sender == bank, "You are not the owner of this contract");
        payable(msg.sender).transfer(feesBalance);
        feesBalance = 0;
    }

    function getBalance() public view returns (uint) {
        require(customerExist[msg.sender], "Account does not exist");
        return customerDetails[msg.sender].AcctBalance;
    }

    function getContractBalance() public view returns (uint) {
        require(msg.sender == bank, "You are not the owner of this contract");
        return address(this).balance;
    }

    function lockBalance(
        uint amount,
        uint unlockTime,
        string memory password
    ) public {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        require(hashedPassword == passwords[msg.sender], "Incorrect password");
        require(customerExist[msg.sender], "Account does not exist");
        require(amount > 0, "Lock amount must be greater than 0");
        require(
            amount <= customerDetails[msg.sender].AcctBalance,
            "Insufficient funds"
        );
        require(
            unlockTime > block.timestamp,
            "Unlock time should be in the future"
        );

        // Check if any of the customer's balances are already locked
        bool isLocked = false;
        for (uint i = 0; i < lockedBalances[msg.sender].length; i++) {
            if (lockedBalances[msg.sender][i].unlockTime > block.timestamp) {
                isLocked = true;
                break;
            }
        }
        require(
            !isLocked,
            "You have locked balances that have not been unlocked yet"
        );

        LockedBalance storage locked = lockedBalances[msg.sender].push();
        locked.amount = amount;
        locked.unlockTime = unlockTime;

        uint bankFee = (amount * 1) / 1000;
        amount -= bankFee;
        feesBalance += bankFee;

        customerDetails[msg.sender].AcctBalance -= amount;

        emit Locked(amount, unlockTime);

        // Automatically unlock balance after the unlock time passes
        if (block.timestamp >= unlockTime) {
            customerDetails[msg.sender].AcctBalance += locked.amount;
            delete lockedBalances[msg.sender][
                lockedBalances[msg.sender].length - 1
            ];
            emit Unlocked(locked.amount, unlockTime);
            // emit Unlocked(locked.amount);
        }
    }

    function unlockBalance() public {
        require(customerExist[msg.sender], "Account does not exist");
        LockedBalance[] storage locked = lockedBalances[msg.sender];
        for (uint i = 0; i < locked.length; i++) {
            require(
                locked[i].unlockTime <= block.timestamp,
                "Balance not yet unlocked"
            );
            customerDetails[msg.sender].AcctBalance += locked[i].amount;
            locked[i].amount = 0;
            locked[i].unlockTime = 0;
        }
    }

    function transferFunds(
        address to,
        uint amount,
        string memory password
    ) public payable {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        require(hashedPassword == passwords[msg.sender], "Incorrect password");
        require(customerExist[msg.sender], "Sender account does not exist");
        require(amount > 0, "Amount must be greater than 0");

        uint availableBalance = customerDetails[msg.sender].AcctBalance;
        for (uint i = 0; i < lockedBalances[msg.sender].length; i++) {
            LockedBalance storage locked = lockedBalances[msg.sender][i];
            if (locked.unlockTime > block.timestamp) {
                availableBalance -= locked.amount;
            }
        }
        require(
            amount <= customerDetails[msg.sender].AcctBalance,
            "Insufficient funds"
        );

        uint bankFee;
        if (customerExist[to]) {
            bankFee = (amount * 1) / 1000;
        } else {
            bankFee = (amount * 3) / 1000;
        }

        uint transferAmount = amount - bankFee;
        customerDetails[msg.sender].AcctBalance -= amount;
        feesBalance += bankFee;

        if (customerExist[to]) {
            customerDetails[to].AcctBalance += transferAmount;
        } else {
            payable(to).transfer(transferAmount);
        }
    }

    function changePassword(
        string memory password,
        string memory newPassword
    ) public {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        require(hashedPassword == passwords[msg.sender], "Incorrect password");
        require(customerExist[msg.sender], "Account does not exist");
        bytes32 newHashedPassword = keccak256(abi.encodePacked(newPassword));
        passwords[msg.sender] = newHashedPassword;
    }

    function deleteAccount(string memory password) public {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        require(hashedPassword == passwords[msg.sender], "Incorrect password");
        require(customerExist[msg.sender], "Account does not exist");
        require(
            customerDetails[msg.sender].AcctBalance == 0,
            "Please withdraw all funds before deleting account"
        );
        // Remove customer data
        customerDetails[msg.sender].AcctBalance = 0;
        passwords[msg.sender] = 0x0;
        customerExist[msg.sender] = false;
    }
}
