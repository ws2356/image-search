export function WeChatScreen() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-xl bg-background px-xl text-center">
      <h2 className="text-xl font-bold text-foreground">请在浏览器中打开</h2>
      <p className="text-sm text-secondary">
        当前微信内置浏览器不支持文件传输功能。请点击右上角「···」按钮，然后选择「在浏览器中打开」即可继续。
      </p>
    </div>
  );
}
