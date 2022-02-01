import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:another_brother/label_info.dart';
import 'package:another_brother/printer_info.dart';
import 'package:another_quickbooks/another_quickbooks.dart';
import 'package:another_quickbooks/quickbook_models.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Quickbooks + Brother Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();

  final String applicationId = "b790c7c7-28bb-4614-898d-d4587";
  final String clientId = "ABNIuyQM0oAR68j9E4qFlXa1wECY4TDah7H7w3urknpWDlgYKA";
  final String clientSecret = "iZU1Dyqh2TNz0Rp01z83SJ4n6XggN2nTGZNHU3AC";
  final String refreshToken =
      "AB11652296788mUqtDdp2TUwNA5qS7VNGMoYqvw9vbNTxDZIel"; //"AB11652210098Wbv587q2tebOcKFcsPRplbRtoqobsvEmI2vVr";
  String? realmId;// = "4620816365213534410";

  // Configured in Quickbooks Dashboard.
  final String redirectUrl =
      "https://developer.intuit.com/v2/OAuth2Playground/RedirectUrl";

  QuickbooksClient? quickClient;
  String? authUrl = "";
  TokenResponse? token;

  @override
  void initState() {
    print("Init Called");
    initializeQuickbooks();
  }
  ///
  /// Initialize Quickbooks Client
  ///
  Future<void> initializeQuickbooks() async {
    quickClient = QuickbooksClient(
        applicationId: applicationId,
        clientId: clientId,
        clientSecret: clientSecret,
    environmentType: EnvironmentType.Sandbox);

    await quickClient!.initialize();
    setState(() {
      authUrl = quickClient!.getAuthorizationPageUrl(
          scopes: [Scope.Payments, Scope.Accounting],
          redirectUrl: redirectUrl,
          state: "state123");
    });
  }

  Future<void> requestAccessToken(String code, String realmId) async {
    this.realmId = realmId;
    token = await quickClient!.getAuthToken(code: code,
        redirectUrl: redirectUrl,
        realmId: realmId);

    setState(() {

    });
  }

  Future<void> printQuickbooksReport() async {

    //////////////////////////////////////////////////
    /// Request the Storage permissions required by
    /// another_brother to print.
    //////////////////////////////////////////////////
    if (!await Permission.storage.request().isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("Access to storage is needed in order print."),
        ),
      ));
      return;
    }

    //////////////////////////////////////////////////
    /// Fetch invoice PDF for Invoice ID: 130
    //////////////////////////////////////////////////
    Uint8List pdfBytes = await quickClient!
        .getAccountingClient()
        .getInvoicePdf(realmId: realmId, invoiceId: "130");

    //////////////////////////////////////////////////
    /// Save PDF to temp memory
    /// The library another_brother requires a PDF
    /// file so we need to save the bytes of the PDF
    /// file obtained through another_quickbooks
    //////////////////////////////////////////////////
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;
    File invoiceFile = File('$path/invoice.pdf');
    invoiceFile.writeAsBytesSync(pdfBytes);

    //////////////////////////////////////////////////
    /// Configure printer
    /// Printer: QL1110NWB
    /// Connection: Bluetooth
    /// Paper Size: W62
    /// Important: Printer must be paired to the
    /// phone for the BT search to find it.
    //////////////////////////////////////////////////
    var printer = Printer();
    var printInfo = PrinterInfo();
    printInfo.printerModel = Model.QL_1110NWB;
    printInfo.printMode = PrintMode.FIT_TO_PAGE;
    printInfo.isAutoCut = true;
    printInfo.port = Port.BLUETOOTH;
    // Set the label type.
    printInfo.labelNameIndex = QL1100.ordinalFromID(QL1100.W62.getId());

    // Set the printer info so we can use the SDK to get the printers.
    await printer.setPrinterInfo(printInfo);

    // Get a list of printers with my model available in the network.
    List<BluetoothPrinter> printers = await printer.getBluetoothPrinters([Model.QL_1110NWB.getName()]);

    if (printers.isEmpty) {
      // Show a message if no printers are found.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("No paired printers found on your device."),
        ),
      ));

      return;
    }
    // Get the IP Address from the first printer found.
    printInfo.macAddress = printers.single.macAddress;
    printer.setPrinterInfo(printInfo);

    // Print Invoice
    printer.printPdfFile(invoiceFile.path, 1);
  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: token == null ? WebView(
          key: ObjectKey(authUrl),
              initialUrl: authUrl,
              javascriptMode: JavascriptMode.unrestricted,
              onWebViewCreated: (WebViewController webViewController) {
                _controller.complete(webViewController);
              },
              onProgress: (int progress) {
                print('WebView is loading (progress : $progress%)');
              },
              javascriptChannels: <JavascriptChannel>{},
              navigationDelegate: (NavigationRequest request) {
                if (request.url.startsWith(redirectUrl)) {
                  print('blocking navigation to $request}');
                  var url = Uri.parse(request.url);
                  String code = url.queryParameters["code"]!;
                  String realmId = url.queryParameters['realmId']!;
                  // Request access token
                  requestAccessToken(code, realmId);

                  return NavigationDecision.prevent;
                }
                print('allowing navigation to $request');
                return NavigationDecision.navigate;
              },
              onPageStarted: (String url) {
                print('Page started loading: $url');
              },
              onPageFinished: (String url) {
                print('Page finished loading: $url');
              },
              gestureNavigationEnabled: true,
              backgroundColor: const Color(0x00000000),
            ): Container(child: Text("Authenticated with Quickbooks"),)
      ),
      floatingActionButton: token != null ? FloatingActionButton(
        onPressed: (){printQuickbooksReport();},
        tooltip: 'Print',
        child: const Icon(Icons.print),
      ): null, // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
