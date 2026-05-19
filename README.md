# PSLedger

A simple command-line double-entry bookkeeping system built as a PowerShell module, using plain text files as storage.

## Installation

```powershell
Install-Module PSLedger
```

## Development

### Prerequisites
- PowerShell 5.1+
- [Pester](https://github.com/pester/Pester) (testing framework)
- [TDDUtils](https://github.com/hansEricG/TDDUtils) (test utilities)
- [TDDSeams](https://github.com/hansEricG/TDDSeams) (mockable seams)

### Running Tests
```powershell
Invoke-Pester ./Tests
```

## License
MIT
