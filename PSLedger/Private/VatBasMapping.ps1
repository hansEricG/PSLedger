# BAS account to Swedish VAT declaration box mapping.
# Skatteverket momsdeklaration — standard boxes.
#
# This maps BAS account ranges to the numeric box numbers used in the Swedish
# VAT return (skattedeklaration för moms).

function Get-VatBoxMapping {
    [CmdletBinding()]
    param()

    @(
        # Box 05 — Momspliktig försäljning (domestic taxable sales)
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^30[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^31[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^32[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^33[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^34[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^35[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^36[0-9]{2}$' }
        [PSCustomObject]@{ Box = 5;  Name = 'Momspliktig försäljning';        AccountPattern = '^37[0-9]{2}$' }

        # Box 10 — Utgående moms 25 %
        [PSCustomObject]@{ Box = 10; Name = 'Utgående moms 25 %';            AccountPattern = '^2610$' }
        [PSCustomObject]@{ Box = 10; Name = 'Utgående moms 25 %';            AccountPattern = '^2611$' }

        # Box 11 — Utgående moms 12 %
        [PSCustomObject]@{ Box = 11; Name = 'Utgående moms 12 %';            AccountPattern = '^2620$' }
        [PSCustomObject]@{ Box = 11; Name = 'Utgående moms 12 %';            AccountPattern = '^2621$' }

        # Box 12 — Utgående moms 6 %
        [PSCustomObject]@{ Box = 12; Name = 'Utgående moms 6 %';             AccountPattern = '^2630$' }
        [PSCustomObject]@{ Box = 12; Name = 'Utgående moms 6 %';             AccountPattern = '^2631$' }

        # Box 48 — Ingående moms
        [PSCustomObject]@{ Box = 48; Name = 'Ingående moms';                 AccountPattern = '^2640$' }
        [PSCustomObject]@{ Box = 48; Name = 'Ingående moms';                 AccountPattern = '^2641$' }
        [PSCustomObject]@{ Box = 48; Name = 'Ingående moms';                 AccountPattern = '^2645$' }
        [PSCustomObject]@{ Box = 48; Name = 'Ingående moms';                 AccountPattern = '^2649$' }
    )
}
