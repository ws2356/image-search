using NUnit.Framework;
using UIAutomationTests.Utilities;
using System.IO;

namespace UIAutomationTests
{
    public class BaseTest
    {
        protected AppLauncher AppLauncher;

        [OneTimeSetUp]
        public void OneTimeSetup()
        {
            var testResultsDir = Path.Combine(TestContext.CurrentContext.WorkDirectory, "TestResults");
            TestLogger.Initialize(testResultsDir);
        }

        [SetUp]
        public void Setup()
        {
            TestLogger.Log($"Starting test: {TestContext.CurrentContext.Test.Name}");
            AppLauncher = new AppLauncher();
            AppLauncher.Launch();
            TestLogger.Log("Application launched successfully.");
        }

        [TearDown]
        public void Teardown()
        {
            var status = TestContext.CurrentContext.Result.Outcome.Status.ToString();
            TestLogger.Log($"Finished test: {TestContext.CurrentContext.Test.Name}. Result: {status}");
            AppLauncher?.Dispose();
            TestLogger.Log("Application closed.");
        }
    }
}
