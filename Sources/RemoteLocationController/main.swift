import ControllerCLI

@main
struct RemoteLocationControllerMain {
  static func main() async {
    await RemoteLocationControllerCommand.main()
  }
}
