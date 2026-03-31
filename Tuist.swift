import ProjectDescription

let tuist = Tuist(
    fullHandle: "zach/mitori",
    project: .tuist(
        generationOptions: .options(
            buildInsightsDisabled: true,
            testInsightsDisabled: true,
            disableSandbox: false,
            enableCaching: true
        )
    )
)
