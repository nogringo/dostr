## 0.1.0

 - Initial release, moved out of the `ndk` package. `Nip13` replaces the `ProofOfWork` usecase. `calculateCommitment` now returns a `BigInt`, so it stays exact past a difficulty of 31 on the web and 62 on the VM.
