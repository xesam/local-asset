import { describe, it, expect } from '@ohos/hypium';
import {
  fileNameFromPickerUri,
  guessImageMime,
  submittedFileName,
} from '../../main/ets/common/PickedImage';

/**
 * 场景 8（compatibility.md §13.8）里从选图 URI 派生文件名 / MIME / 落地名的逻辑。
 *
 * 选图与落盘本身在本仓无法自动化（需要真机相册与用户交互，由真机验收覆盖），
 * 但这几段字符串派生是纯函数，且其中两处直接关系到**安全与可用性**：
 *  - 文件名里的 `/` 若不净化，落地路径会写到别的目录去；
 *  - 文件名为空会让 handle URI 的末段为空，成为一条反查不回来的 URI。
 */
export default function pickedImageTest() {
  describe('PickedImage', () => {
    it('takes the last segment of a photoAccessHelper URI', 0, () => {
      expect(fileNameFromPickerUri('file://media/Photo/12/IMG_001/IMG_20240101_120000.jpg'))
        .assertEqual('IMG_20240101_120000.jpg');
    });

    it('strips query and fragment before taking the file name', 0, () => {
      // 不剔除的话文件名里会混进 `?xxx`，既污染 handle URI 的末段，
      // 也污染落地文件名。
      expect(fileNameFromPickerUri('file://media/a/b.jpg?width=100')).assertEqual('b.jpg');
      expect(fileNameFromPickerUri('file://media/a/b.jpg#frag')).assertEqual('b.jpg');
      expect(fileNameFromPickerUri('file://media/a/b.jpg?w=1#f')).assertEqual('b.jpg');
    });

    it('falls back to picked-image when no last segment survives', 0, () => {
      // 空文件名会让 registerHandle 铸造出 `.../<token>/` —— 末段为空，反查走不通。
      expect(fileNameFromPickerUri('file://media/a/')).assertEqual('picked-image');
      expect(fileNameFromPickerUri('')).assertEqual('picked-image');
    });

    it('guesses image MIME by extension, case-insensitively', 0, () => {
      expect(guessImageMime('a.png')).assertEqual('image/png');
      expect(guessImageMime('a.PNG')).assertEqual('image/png');
      expect(guessImageMime('a.webp')).assertEqual('image/webp');
      expect(guessImageMime('a.gif')).assertEqual('image/gif');
      expect(guessImageMime('a.heic')).assertEqual('image/heic');
    });

    it('falls back to image/jpeg rather than octet-stream', 0, () => {
      // 语境已限定为"从相册选出来的图片"：回落到 jpeg 比回落到 octet-stream
      // 更贴近事实，也让 <img> 预览不至于因 Content-Type 被当成下载。
      // 这是本场景的局部约定，不是库的推断策略（后者见 webview guessMimeType）。
      expect(guessImageMime('noext')).assertEqual('image/jpeg');
      expect(guessImageMime('a.jpg')).assertEqual('image/jpeg');
      expect(guessImageMime('a.jpeg')).assertEqual('image/jpeg');
    });

    it('sanitises path separators out of the submitted file name', 0, () => {
      // record.fileName 保留的是调用方给的**原名**（InMemoryHandleRegistry 只净化
      // URI 段，不动 record），其中可能含 `/`。不净化就会写到别的目录去，
      // 或因中间目录不存在而 open 失败。
      expect(submittedFileName('a/b.jpg')).assertEqual('submitted-a_b.jpg');
      expect(submittedFileName('../../etc/passwd')).assertEqual('submitted-.._.._etc_passwd');
    });

    it('keeps the characters that are safe in a sandbox path', 0, () => {
      expect(submittedFileName('IMG_2024-01-01.v2.jpg')).assertEqual('submitted-IMG_2024-01-01.v2.jpg');
    });

    it('never produces a bare submitted- prefix with an empty name', 0, () => {
      expect(submittedFileName('')).assertEqual('submitted-picked-image');
    });
  });
}
