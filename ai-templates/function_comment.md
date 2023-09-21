Here is a template for the function comments. Always use this format when documenting functions.

```move
/// <ONE LINE FUNCTION DESCRIPTION HERE>
/// 
/// # Arguments
/// 
/// * `parameter1` - <SMALL DESCRIPTION OF THE PARAMETER>
/// * `parameter2` - <SMALL DESCRIPTION OF THE PARAMETER>
/// * `parameter3` - <SMALL DESCRIPTION OF THE PARAMETER>
/// * `parameter4` - <SMALL DESCRIPTION OF THE PARAMETER>
entry public fun function_name(
    parameter1: Type1,
    parameter2: Type2,
    parameter3: Type3,
    parameter4: Type4,
) {
    <FUNCTION BODY HERE>
}
```

If there are no parameters, remove the `# Arguments` section.

If the function returns a value, add a `# Returns` section.
