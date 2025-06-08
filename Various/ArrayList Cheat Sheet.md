
# 🧠 PowerShell `ArrayList` Cheat Sheet

### 🔹 Declaration

```powershell
$ArrayList = New-Object System.Collections.ArrayList
# or
$ArrayList = [System.Collections.ArrayList]::new()
```

---

### ➕ Add Element

```powershell
$ArrayList.Add("abc")
$ArrayList.Add(1500)
```

---

### 🧹 Clear All Elements

```powershell
$ArrayList.Clear()
```

---

### 🔎 Get Index of an Element

```powershell
$ArrayList.IndexOf(999)
```

---

### ❓ Check if Element Exists

```powershell
$ArrayList.Contains(1500)
```

---

### 📋 Copy a Range of Elements

```powershell
$copy = $ArrayList[1..3]
```

---

### 🔁 Get Enumerator

```powershell
$ArrayList.GetEnumerator()
```

---

### 📐 Get Sublist (GetRange)

```powershell
$ArrayList.GetRange(1, 2)
```

---

### 📌 Insert Element at Specific Index

```powershell
$ArrayList.Insert(1, "new-value")
```

---

### ❌ Remove Element by Value

```powershell
$ArrayList.Remove("abc")
```

---

### ❌ Remove Element by Index

```powershell
$ArrayList.RemoveAt(2)
```

---

### ❌ Remove Range of Elements

```powershell
$ArrayList.RemoveRange(0, 2)
```

---

### 🔄 Reverse the Order

```powershell
$ArrayList.Reverse()
# Or partially:
$ArrayList.Reverse(1, 3)
```

---

### 🔤 Sort the ArrayList

```powershell
$ArrayList.Sort()
# Or using pipeline (if types are sortable):
$ArrayList | Sort-Object
```

---

### 🧾 Bonus: Example of Hashtable (for comparison)

```powershell
$ageList = @{}
$ageList["Kevin"] = 35
$ageList["Alex"] = 9
```


