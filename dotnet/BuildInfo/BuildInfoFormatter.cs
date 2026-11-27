namespace BuildInfo;

/// <summary>
/// Tiny library that mirrors what the Python service reports at /version.
/// It exists so the pipeline can show the same restore/build/test pattern
/// for a .NET project; swap it for a real service in practice.
/// </summary>
public static class BuildInfoFormatter
{
    public static string Describe(string environment, string version)
    {
        if (string.IsNullOrWhiteSpace(environment))
            throw new ArgumentException("environment is required", nameof(environment));
        if (string.IsNullOrWhiteSpace(version))
            throw new ArgumentException("version is required", nameof(version));

        return $"{environment}@{version}";
    }
}
