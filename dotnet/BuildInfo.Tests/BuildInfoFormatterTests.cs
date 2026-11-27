using BuildInfo;
using Xunit;

namespace BuildInfo.Tests;

public class BuildInfoFormatterTests
{
    [Fact]
    public void Describe_CombinesEnvironmentAndVersion()
    {
        Assert.Equal("dev@abc123", BuildInfoFormatter.Describe("dev", "abc123"));
    }

    [Theory]
    [InlineData("", "abc123")]
    [InlineData("dev", " ")]
    public void Describe_RejectsMissingValues(string environment, string version)
    {
        Assert.Throws<ArgumentException>(() => BuildInfoFormatter.Describe(environment, version));
    }
}
