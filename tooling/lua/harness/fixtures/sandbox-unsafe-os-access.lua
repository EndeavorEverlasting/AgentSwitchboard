-- Negative contract fixture only. Validators classify this source; they do not execute it.
-- This is intentionally incompatible with the deny-by-default sandbox contract.
return os.getenv("HOME")
