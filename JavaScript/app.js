// ===============================
// SPECTRO - Frontend Controller
// ===============================

// Tipos EIP-712
const types = {
    Intent: [
        { name: "sender", type: "address" },
        { name: "destinationChain", type: "uint256" },
        { name: "amount", type: "uint256" },
        { name: "nonce", type: "uint256" }
    ]
};

// Elementos
const connectBtn = document.getElementById("connect-wallet");
const signBtn = document.getElementById("sign-btn");
const amountInput = document.getElementById("amount");
const nonceDisplay = document.getElementById("nonce-display");
const logList = document.getElementById("log-list");

let userAddress = null;
const targetChainIdHex = "0xaa36a7"; // Sepolia

// ===============================
// UTIL
// ===============================

function addLog(message) {
    if (!logList) return;
    const li = document.createElement("li");
    li.innerText = `• ${message}`;
    logList.prepend(li);
}

// ===============================
// CONNECT WALLET
// ===============================

async function connectWallet() {
    if (!window.ethereum) {
        alert("MetaMask not found!");
        return;
    }

    try {
        addLog("Requesting wallet login...");

        // 🔥 O segredo está aqui: isso força a MetaMask a abrir a tela de login/seleção
        await window.ethereum.request({
            method: "wallet_requestPermissions",
            params: [{ eth_accounts: {} }]
        });

        // Após a permissão/login, pegamos a conta
        const accounts = await window.ethereum.request({
            method: "eth_requestAccounts"
        });

        userAddress = accounts[0];

        // Força a rede correta (Sepolia/0xaa36a7)
        const currentChainId = await window.ethereum.request({
            method: "eth_chainId"
        });

        if (currentChainId !== targetChainIdHex) {
            addLog("Switching network...");
            try {
                await window.ethereum.request({
                    method: "wallet_switchEthereumChain",
                    params: [{ chainId: targetChainIdHex }]
                });
            } catch (switchError) {
                addLog("Please switch network manually.");
                return;
            }
        }

        // Atualiza a UI
        connectBtn.innerText = `Connected: ${userAddress.substring(0, 6)}...`;
        connectBtn.style.background = "#00ff88";
        signBtn.disabled = false;
        signBtn.style.cursor = "pointer";
        signBtn.style.opacity = "1";

        addLog(`Wallet verified: ${userAddress}`);
        if (nonceDisplay) nonceDisplay.innerText = "0";

    } catch (error) {
        addLog("Login or connection denied.");
        console.error(error);
    }
}

// ===============================
// SIGN INTENT
// ===============================

async function signIntent() {
    if (!userAddress) {
        alert("Please connect your wallet first!");
        return;
    }

    const amount = amountInput.value;
    const selectElement = document.getElementById("destination");
    const destinationChain = selectElement.value;
    // Captura o nome da rede (ex: "Optimism" ou "Arbitrum One") para o log dinâmico
    const targetNetworkName = selectElement.options[selectElement.selectedIndex].text;
    const nonce = 0;

    if (!amount || amount <= 0) {
        addLog("Error: Invalid amount.");
        alert("Enter a valid amount");
        return;
    }

    try {
        addLog("Requesting EIP-712 signature...");

        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const network = await provider.getNetwork();

        const domain = {
            name: "SPECTRO_PROTOCOL",
            version: "1",
            chainId: network.chainId,
            verifyingContract: "0x1111111111111111111111111111111111111111"
        };

        const message = {
            sender: userAddress,
            destinationChain: Number(destinationChain),
            amount: ethers.utils.parseUnits(amount, 6).toString(),
            nonce: Number(nonce)
        };

        const msgParams = JSON.stringify({
            domain,
            message,
            primaryType: "Intent",
            types: {
                EIP712Domain: [
                    { name: "name", type: "string" },
                    { name: "version", type: "string" },
                    { name: "chainId", type: "uint256" },
                    { name: "verifyingContract", type: "address" }
                ],
                ...types
            }
        });

        const signature = await window.ethereum.request({
            method: "eth_signTypedData_v4",
            params: [userAddress, msgParams]
        });

        addLog("SUCCESS: Intent Signed!");
        console.log("Signature:", signature);

        // --- SIMULAÇÃO DINÂMICA (A ALMA DO PROJETO) ---
        setTimeout(() => {
            // Agora usa o nome da rede selecionada no log
            addLog(`Relaying intent to Solver pool for ${targetNetworkName}...`, "info");
            document.getElementById("liquidity-check").innerText = "Match Found!";
            document.getElementById("liquidity-check").style.color = "#00ff88";
        }, 2000);

        setTimeout(() => {
            // O log agora confirma a rede correta dinamicamente
            addLog(`Transaction Finalized on ${targetNetworkName}!`, "success");
            nonceDisplay.innerText = "1"; 
        }, 5000);

    } catch (err) {
        addLog("FAILED: Signature rejected.");
        console.error(err);
    }
}

// ===============================
// EVENTS
// ===============================

if (connectBtn) connectBtn.addEventListener("click", connectWallet);
if (signBtn) {
    signBtn.disabled = true;
    signBtn.style.opacity = "0.5";
    signBtn.style.cursor = "not-allowed";
    signBtn.addEventListener("click", signIntent);
}