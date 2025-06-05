$Name = "François-○<>??Dupont!?!#@$%^&*()_+\|}{○<>??/ €$¥£¢ \^$.|?*+()[{ 0123456789"
$Name -replace '[^a-zA-Z]', ''

# Result  = FranoisDupont

$Login = "François-○<>??Dupont!?!#@$%^&*()_+\|}{○<>??/ €$¥£¢ \^$.|?*+()[{ 0123456789"
$Login -replace '[^a-zA-Z0-9]', ''

# Result  = FranoisDupont0123456789
