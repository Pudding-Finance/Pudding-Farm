pragma solidity 0.6.12;

import "./libs/math/SafeMath.sol";
import "./libs/token/ORC20/IORC20.sol";
import "./libs/token/ORC20/SafeORC20.sol";
import "./libs/access/Ownable.sol";
import "./libs/utils/EnumerableSet.sol";

contract UserProfile is Ownable {
    using SafeMath for uint256;
    using SafeORC20 for IORC20;
    // Add the library methods
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        string avatar;
    }

    // The PUD TOKEN!
    IORC20 public pud;

    // the cost to set a avatar
    uint256 public avatarCost;

    // all registed users
    EnumerableSet.AddressSet private users;

    // address => userinfo
    mapping(address => UserInfo) private userInfo;

    event SetAvatar(address indexed user, string avatar);
    event Withdraw(address indexed user, uint256 amount);

    constructor(IORC20 _pud, uint256 _avatarCost) public {
        pud = _pud;
        avatarCost = _avatarCost;
    }

    function getTotalUsers() external view onlyOwner returns (uint256) {
        return users.length();
    }

    function getUserAvatarOf(address user)
        external
        view
        onlyOwner
        returns (string memory)
    {
        require(users.contains(user), "address is not valid");

        return userInfo[user].avatar;
    }

    function getUserAvatarAt(uint256 index)
        external
        view
        onlyOwner
        returns (string memory)
    {
        require(index < users.length(), "index is not valid");

        return userInfo[users.at(index)].avatar;
    }

    function hasAvatar(address _address) external view returns (bool) {
        UserInfo storage user = userInfo[_address];
        return bytes(user.avatar).length != 0;
    }

    function setAvatarCost(uint256 _avatarCost) external onlyOwner {
        avatarCost = _avatarCost;
    }

    function getAvatar() external view returns (string memory) {
        return userInfo[msg.sender].avatar;
    }

    function setAvatar(string calldata avatar) external {
        UserInfo storage user = userInfo[msg.sender];

        require(bytes(user.avatar).length == 0, "avatar has already been set");

        pud.safeTransferFrom(address(msg.sender), address(this), avatarCost);
        user.avatar = avatar;

        users.add(msg.sender);

        emit SetAvatar(msg.sender, avatar);
    }

    function withdraw(uint256 amount) external onlyOwner {
        pud.safeTransfer(address(msg.sender), amount);

        emit Withdraw(msg.sender, amount);
    }
}
