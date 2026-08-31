// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface ISwapRouterV2 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

// ============================================================================
// NOTICE
// ============================================================================
// PERSONAL / SELF-CUSTODY only. Deploy your own instance. The deployer is
// owner and the only intended operator.
//
// - depositEth() / receive() accept ETH from any address but do NOT track
//   per-depositor shares.
// - withdraw / withdrawETH / emergencyWithdrawAll are owner-only and can
//   move the full balance.
// - executeArbitrage / executeArbitrageFromBalance are owner-gated on the
//   from-balance path; the payable path spends msg.sender funds.
//
// Do not pool other people's money in this contract.
//
// FUNDING: any amount of ETH or allowed ERC-20. No 0.5–1 ETH minimum.
// Keep spare ETH on the owner wallet for gas.
//
// Cards: this contract cannot take debit/credit cards. Buy ETH/USDC with a
// card via an on-ramp (MetaMask Buy, Coinbase, MoonPay, …) into the owner
// wallet, then transfer / depositEth() here. Never collect card numbers in
// a bot UI. See docs/CARD_ONRAMP.md.
// ============================================================================

contract Arbitrage {
    address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant NATIVE = address(0);

    address public owner;
    mapping(address => bool) private allowed;
    mapping(address => bool) private allowedRouters;
    bool private paused;
    uint256 private _reentrancyLock = 1;

    address private defaultTokenOut;
    uint24 private defaultFee = 3000;

    // Any size is allowed for funding. Quick-swap rails are wide so small
    // tests (0.001 ETH) and larger inventory both work. Owner can retune.
    uint256 private minQuickSwapAmount = 0.001 ether;
    uint256 private maxQuickSwapAmount = 100 ether;

    event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event ArbitrageExecuted(address indexed user, uint256 legsCount, uint256 amountIn, uint256 amountOut);
    event TokenAllowedSet(address indexed token, bool allowedFlag);
    event RouterAllowedSet(address indexed router, bool allowedFlag);
    event PausedSet(bool paused);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event EmergencyWithdrawAll(address indexed to);
    event Deposit(address indexed from, uint256 amount);
    event DefaultTokenOutSet(address indexed token);
    event DefaultFeeSet(uint24 fee);
    event MinQuickSwapAmountSet(uint256 amount);
    event MaxQuickSwapAmountSet(uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyLock == 1, "Reentrancy");
        _reentrancyLock = 2;
        _;
        _reentrancyLock = 1;
    }

    constructor() {
        owner = msg.sender;
        allowed[WETH] = true;
        allowed[USDT] = true;
        allowed[USDC] = true;
        allowed[WBTC] = true;
        allowedRouters[ROUTER] = true;
        defaultTokenOut = USDT;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function depositEth() external payable {
        require(msg.value > 0, "Zero deposit");
        emit Deposit(msg.sender, msg.value);
    }

    function setTokenAllowed(address token, bool isAllowed) external onlyOwner {
        allowed[token] = isAllowed;
        emit TokenAllowedSet(token, isAllowed);
    }

    function setRouterAllowed(address router, bool isAllowed) external onlyOwner {
        require(router != address(0), "Zero address");
        allowedRouters[router] = isAllowed;
        emit RouterAllowedSet(router, isAllowed);
    }

    function setPaused(bool isPaused) external onlyOwner {
        paused = isPaused;
        emit PausedSet(isPaused);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        require(amount > 0, "Zero amount");
        if (token == NATIVE) {
            require(address(this).balance >= amount, "Insufficient ETH");
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            _safeTransfer(token, to, amount);
        }
        emit Withdraw(token, to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        require(amount > 0 && address(this).balance >= amount, "Bad amount");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
        emit Withdraw(NATIVE, to, amount);
    }

    function emergencyWithdrawAll(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool success, ) = to.call{value: ethBal}("");
            require(success, "ETH transfer failed");
            emit Withdraw(NATIVE, to, ethBal);
        }
        emit EmergencyWithdrawAll(to);
    }

    function setDefaultTokenOut(address token) external onlyOwner {
        require(token != address(0), "Zero address");
        defaultTokenOut = token;
        allowed[token] = true;
        emit DefaultTokenOutSet(token);
    }

    function setDefaultFee(uint24 fee) external onlyOwner {
        require(fee == 100 || fee == 500 || fee == 3000 || fee == 10000, "Bad fee");
        defaultFee = fee;
        emit DefaultFeeSet(fee);
    }

    function setMinQuickSwapAmount(uint256 amount) external onlyOwner {
        require(amount <= maxQuickSwapAmount, "Min > max");
        minQuickSwapAmount = amount;
        emit MinQuickSwapAmountSet(amount);
    }

    function setMaxQuickSwapAmount(uint256 amount) external onlyOwner {
        require(amount >= minQuickSwapAmount, "Max < min");
        maxQuickSwapAmount = amount;
        emit MaxQuickSwapAmountSet(amount);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(token != address(0) && to != address(0), "Zero address");
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(token != address(0) && from != address(0) && to != address(0), "Zero address");
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }

    function _getAllowance(address token, address tokenOwner, address spender) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, tokenOwner, spender)
        );
        require(success && data.length >= 32, "Allowance call failed");
        return abi.decode(data, (uint256));
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == NATIVE) return account.balance;
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0x70a08231, account)
        );
        require(success && data.length >= 32, "BalanceOf call failed");
        return abi.decode(data, (uint256));
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = _getAllowance(token, address(this), spender);
        if (currentAllowance < amount) {
            if (currentAllowance > 0) {
                _safeApprove(token, spender, 0);
            }
            _safeApprove(token, spender, type(uint256).max);
        }
    }

    function _firstToken(bytes calldata path) internal pure returns (address) {
        require(path.length >= 20, "Invalid path");
        return address(bytes20(path[0:20]));
    }

    function _lastToken(bytes calldata path) internal pure returns (address) {
        require(path.length >= 20, "Invalid path");
        return address(bytes20(path[path.length - 20:]));
    }

    function _unwrapAndSend(uint256 amount, address payable to) internal {
        (bool success, ) = WETH.call(abi.encodeWithSelector(0x2e1a7d4d, amount));
        require(success, "WETH withdraw failed");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "ETH send failed");
    }

    function swap(
        bytes calldata path,
        bool etherIn,
        bool etherOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 43, "Invalid path");
        require(amountIn > 0, "Zero amount");

        address tokenIn = _firstToken(path);
        address tokenOut = _lastToken(path);
        require(allowed[tokenOut], "Token not allowed");

        if (etherIn) {
            require(msg.value == amountIn, "Wrong msg.value");
            require(tokenIn == WETH, "Path must start with WETH");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        amountOut = _executeSwap(path, etherIn, etherOut, amountIn, amountOutMinimum, deadline);
        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _executeSwap(
        bytes calldata path,
        bool etherIn,
        bool etherOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        address tokenIn = _firstToken(path);
        if (!etherIn) {
            _approveIfNeeded(tokenIn, ROUTER, amountIn);
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: etherOut ? address(this) : msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        if (etherIn) {
            amountOut = ISwapRouter(ROUTER).exactInput{value: amountIn}(params);
        } else {
            amountOut = ISwapRouter(ROUTER).exactInput(params);
        }

        if (etherOut) {
            _unwrapAndSend(amountOut, payable(msg.sender));
        }
    }

    function quickSwap(uint256 amountOutMinimum) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(msg.value >= minQuickSwapAmount, "Amount too small for quick swap");
        require(msg.value <= maxQuickSwapAmount, "Amount too large for quick swap");
        require(defaultTokenOut != address(0), "Default token not set");

        bytes memory path = abi.encodePacked(WETH, defaultFee, defaultTokenOut);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: msg.value,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = ISwapRouter(ROUTER).exactInput{value: msg.value}(params);
        emit Swapped(msg.sender, WETH, defaultTokenOut, msg.value, amountOut);
    }

    function quickSwapFromBalance(uint256 amountIn, uint256 amountOutMinimum) external onlyOwner nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(amountIn >= minQuickSwapAmount, "Balance too small");
        require(amountIn <= maxQuickSwapAmount, "Balance too large");
        require(amountIn <= address(this).balance, "Insufficient ETH");
        require(defaultTokenOut != address(0), "Default token not set");

        bytes memory path = abi.encodePacked(WETH, defaultFee, defaultTokenOut);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = ISwapRouter(ROUTER).exactInput{value: amountIn}(params);
        emit Swapped(msg.sender, WETH, defaultTokenOut, amountIn, amountOut);
    }

    struct SwapLeg {
        address router;
        bytes path;
        uint256 amountOutMinimum;
        bool useV2;
        address[] v2Path;
    }

    function executeArbitrage(
        SwapLeg[] calldata legs,
        uint256 amountIn,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Expired");
        require(legs.length > 0 && legs.length <= 8, "Invalid legs count");
        require(amountIn > 0, "Zero amount");

        bool isEth = msg.value > 0;
        if (isEth) {
            require(msg.value == amountIn, "Wrong msg.value");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            address tokenIn = legs[0].useV2 ? _v2First(legs[0].v2Path) : _firstToken(legs[0].path);
            _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        amountOut = _runLegs(legs, amountIn, isEth, deadline);
        _payoutFinal(legs, amountOut, msg.sender);
        emit ArbitrageExecuted(msg.sender, legs.length, amountIn, amountOut);
    }

    function executeArbitrageFromBalance(
        SwapLeg[] calldata legs,
        uint256 amountIn,
        uint256 deadline
    ) external onlyOwner nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Expired");
        require(legs.length > 0 && legs.length <= 8, "Invalid legs count");
        require(amountIn > 0, "Zero amount");

        bool isEth;
        if (legs[0].useV2) {
            address tokenIn = _v2First(legs[0].v2Path);
            if (tokenIn == WETH && address(this).balance >= amountIn) {
                isEth = true;
            } else {
                require(_balanceOf(tokenIn, address(this)) >= amountIn, "Insufficient token");
            }
        } else {
            address tokenIn = _firstToken(legs[0].path);
            if (tokenIn == WETH && address(this).balance >= amountIn) {
                isEth = true;
            } else {
                require(_balanceOf(tokenIn, address(this)) >= amountIn, "Insufficient token");
            }
        }

        amountOut = _runLegs(legs, amountIn, isEth, deadline);
        _payoutFinal(legs, amountOut, msg.sender);
        emit ArbitrageExecuted(msg.sender, legs.length, amountIn, amountOut);
    }

    function _v2First(address[] calldata v2Path) internal pure returns (address) {
        require(v2Path.length >= 2, "Bad v2 path");
        return v2Path[0];
    }

    function _runLegs(
        SwapLeg[] calldata legs,
        uint256 amountIn,
        bool isEth,
        uint256 deadline
    ) internal returns (uint256 currentAmount) {
        currentAmount = amountIn;
        for (uint256 i = 0; i < legs.length; i++) {
            currentAmount = _swapLeg(legs[i], currentAmount, isEth && i == 0, deadline);
            isEth = false;
        }
    }

    function _payoutFinal(SwapLeg[] calldata legs, uint256 amountOut, address to) internal {
        SwapLeg calldata lastLeg = legs[legs.length - 1];
        address finalToken = lastLeg.useV2
            ? lastLeg.v2Path[lastLeg.v2Path.length - 1]
            : _lastToken(lastLeg.path);

        require(allowed[finalToken], "Final token not allowed");
        if (finalToken == WETH) {
            _safeTransfer(WETH, to, amountOut);
        } else {
            _safeTransfer(finalToken, to, amountOut);
        }
    }

    function _swapLeg(
        SwapLeg calldata leg,
        uint256 amountIn,
        bool etherIn,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        require(allowedRouters[leg.router], "Router not allowed");

        if (leg.useV2) {
            require(leg.v2Path.length >= 2, "Bad v2 path");
            address tokenIn = leg.v2Path[0];
            if (!etherIn) {
                _approveIfNeeded(tokenIn, leg.router, amountIn);
            }

            uint256[] memory amounts;
            if (etherIn) {
                amounts = ISwapRouterV2(leg.router).swapExactETHForTokens{value: amountIn}(
                    leg.amountOutMinimum,
                    leg.v2Path,
                    address(this),
                    deadline
                );
            } else {
                amounts = ISwapRouterV2(leg.router).swapExactTokensForTokens(
                    amountIn,
                    leg.amountOutMinimum,
                    leg.v2Path,
                    address(this),
                    deadline
                );
            }
            amountOut = amounts[amounts.length - 1];
        } else {
            address tokenIn = _firstToken(leg.path);
            if (!etherIn) {
                _approveIfNeeded(tokenIn, leg.router, amountIn);
            }

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: leg.path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: leg.amountOutMinimum
            });

            if (etherIn) {
                amountOut = ISwapRouter(leg.router).exactInput{value: amountIn}(params);
            } else {
                amountOut = ISwapRouter(leg.router).exactInput(params);
            }
        }
    }

    function getBalance(address token) external view returns (uint256) {
        return _balanceOf(token, address(this));
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function isTokenAllowed(address token) external view returns (bool) {
        return allowed[token];
    }

    function isRouterAllowed(address router) external view returns (bool) {
        return allowedRouters[router];
    }

    function isPaused() external view returns (bool) {
        return paused;
    }

    function getQuickSwapLimits() external view returns (uint256 minAmount, uint256 maxAmount) {
        return (minQuickSwapAmount, maxQuickSwapAmount);
    }

    function revokeApproval(address token, address spender) external onlyOwner {
        _safeApprove(token, spender, 0);
    }
}
