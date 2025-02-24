/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

@testable import DatadogExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest

class DatadogExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWhenExportSpanIsCalled_thenTraceAndLogsAreUploaded() throws {
        var logsSent = false
        var tracesSent = false
        let expecTrace = expectation(description: "trace received")
        expecTrace.assertForOverFulfill = false
        let expecLog = expectation(description: "logs received")
        expecLog.assertForOverFulfill = false

        let server = HttpTestServer(url: URL(string: "http://localhost:33333"),
                                    config: HttpTestServerConfig(tracesReceivedCallback: {
                                        tracesSent = true
                                        expecTrace.fulfill()
                                    },
                                                                 logsReceivedCallback: {
                                        logsSent = true
                                        expecLog.fulfill()
        }))
        DispatchQueue.global(qos: .default).async {
            do {
                try server.start()
            } catch {
                XCTFail()
                return
            }
        }
        let instrumentationLibraryName = "SimpleExporter"
        let instrumentationLibraryVersion = "semver:0.1.0"

        let tracer = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: instrumentationLibraryName, instrumentationVersion: instrumentationLibraryVersion) as! TracerSdk

        let exporterConfiguration = ExporterConfiguration(serviceName: "serviceName",
                                                          resource: "resource",
                                                          applicationName: "applicationName",
                                                          applicationVersion: "applicationVersion",
                                                          environment: "environment",
                                                          clientToken: "clientToken",
                                                          apiKey: "apikey",
                                                          endpoint: Endpoint.custom(
                                                              tracesURL: URL(string: "http://localhost:33333/traces")!,
                                                              logsURL: URL(string: "http://localhost:33333/logs")!,
                                                              metricsURL: URL(string: "http://localhost:33333/metrics")!),
                                                          uploadCondition: { true })

        let datadogExporter = try! DatadogExporter(config: exporterConfiguration)

        let spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(spanProcessor)

        simpleSpan(tracer: tracer)
        spanProcessor.shutdown()

        let result = XCTWaiter().wait(for: [expecTrace, expecLog], timeout: 20, enforceOrder: false)

        if result == .completed {
            XCTAssertTrue(logsSent)
            XCTAssertTrue(tracesSent)
        } else {
            XCTFail()
        }

        server.stop()
    }

    private func simpleSpan(tracer: TracerSdk) {
        let span = tracer.spanBuilder(spanName: "SimpleSpan").setSpanKind(spanKind: .client).startSpan()
        span.addEvent(name: "My event", timestamp: Date())
        span.end()
    }

    func testWhenExportMetricIsCalled_thenMetricsAreUploaded() throws {
        var metricsSent = false
        let expecMetrics = expectation(description: "metrics received")
        expecMetrics.assertForOverFulfill = false

        let server = HttpTestServer(url: URL(string: "http://localhost:33333"),
                                    config: HttpTestServerConfig(metricsReceivedCallback: {
                                        metricsSent = true
                                        expecMetrics.fulfill()
        }))
        DispatchQueue.global(qos: .default).async {
            do {
                try server.start()
            } catch {
                XCTFail()
                return
            }
        }

        let exporterConfiguration = ExporterConfiguration(serviceName: "serviceName",
                                                          resource: "resource",
                                                          applicationName: "applicationName",
                                                          applicationVersion: "applicationVersion",
                                                          environment: "environment",
                                                          clientToken: "clientToken",
                                                          apiKey: "apikey",
                                                          endpoint: Endpoint.custom(
                                                              tracesURL: URL(string: "http://localhost:33333/traces")!,
                                                              logsURL: URL(string: "http://localhost:33333/logs")!,
                                                              metricsURL: URL(string: "http://localhost:33333/metrics")!),
                                                          uploadCondition: { true })

        let datadogExporter = try! DatadogExporter(config: exporterConfiguration)


        let meter = MeterProviderSdk(metricProcessor: UngroupedBatcher(),
                                     metricExporter: datadogExporter,
                                     metricPushInterval: 0.1).get(instrumentationName: "MyMeter")

        let testCounter = meter.createIntCounter(name: "MyCounter")

        testCounter.add(value: 100, labelset: LabelSet.empty)

        let result = XCTWaiter().wait(for: [expecMetrics], timeout: 20)

        if result == .completed {
            XCTAssertTrue(metricsSent)
        } else {
            XCTFail()
        }

        server.stop()
    }
}
