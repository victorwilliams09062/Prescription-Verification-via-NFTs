# Prescription Verification via NFTs
A secure and transparent way to manage medical prescriptions using NFTs on the Stacks blockchain.

## 🎯 Features

- Issue digital prescriptions as NFTs
- Verify prescription authenticity
- Track prescription status
- Prevent double-filling of prescriptions
- Manage authorized doctors and pharmacies

## 🔧 Smart Contract Functions

### Administrative Functions
- `register-doctor`: Register an authorized doctor
- `register-pharmacy`: Register an authorized pharmacy

### Core Functions
- `issue-prescription`: Create a new prescription NFT
- `fill-prescription`: Mark a prescription as filled by a pharmacy
- `get-prescription`: View prescription details
- `verify-prescription`: Check prescription validity

## 🚀 Usage

1. Deploy the contract using Clarinet
2. Register authorized doctors and pharmacies
3. Doctors can issue prescriptions to patients
4. Pharmacies can verify and fill prescriptions
5. Anyone can verify prescription authenticity

## 🔐 Security Features

- Only authorized doctors can issue prescriptions
- Only authorized pharmacies can fill prescriptions
- Prescriptions have expiration dates
- Each prescription can only be filled once
- All transactions are recorded on-chain

## 📝 Example Flow

```clarity
;; Register a doctor
(contract-call? .prescription-verification register-doctor 'DOCTOR_ADDRESS)

;; Issue prescription
(contract-call? .prescription-verification issue-prescription 'PATIENT_ADDRESS "Amoxicillin" "500mg" u30 u7)

;; Fill prescription
(contract-call? .prescription-verification fill-prescription u1)
```
```
