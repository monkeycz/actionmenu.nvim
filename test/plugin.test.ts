import assert from "assert";
import {vimRunner} from "nvim-test-js";
import * as path from "path";
import {ENTER, ESC, openActionMenu} from "./helpers";
import {callbackResult, isComplexItem} from "./helpers/callback";

const withVim = vimRunner(
  {vimrc: path.resolve(__dirname, "helpers", "vimrc.vim")}
)

describe("actionmenu", () => {
  it("loads the test vimrc", () =>
    withVim(async nvim => {
      const loaded = (await nvim.getVar("test_vimrc_loaded")) as boolean;

      assert.equal(loaded, true);
    }));

  it("can set and read a line", () =>
    withVim(async nvim => {
      await nvim.setLine("Foo");

      const line = await nvim.getLine();

      assert.equal(line, "Foo");
    }));

  it("doesn't open the pum initially", () =>
    withVim(async nvim => {
      const visible = await nvim.call("pumvisible");

      assert.equal(visible, 0);
    }));

  it("does nothing when opened with an empty list", () =>
    withVim(async nvim => {
      const initialWindows = await nvim.call("nvim_list_wins");

      await openActionMenu(nvim, []);

      const subsequentWindows = await nvim.call("nvim_list_wins");

      assert.equal(initialWindows.length, subsequentWindows.length);
    }));

  it("opens the pum when called", () =>
    withVim(async nvim => {
      await openActionMenu(nvim, ["One", "Two", "Three"]);

      const visible = await nvim.call("pumvisible");

      assert.equal(visible, 1);
    }));

  it("successfully opens the pum when nomodifiable is set globally", () =>
    withVim(async nvim => {
      await nvim.command("set nomodifiable");
      await openActionMenu(nvim, ["One", "Two", "Three"]);

      const visible = await nvim.call("pumvisible");

      assert.equal(visible, 1);
    }));

  describe("navigating the menu", () => {
    it("moves up and down with j and k", () =>
      withVim(async nvim => {
        await openActionMenu(nvim, ["One", "Two", "Three"]);

        await nvim.call("feedkeys", [`jjk${ENTER}`]);

        const {index, item} = await callbackResult(nvim);

        assert.equal(index, 1);
        assert.equal(item, "Two");
      }));
  });

  describe("opening and closing the menu", () => {
    it("starts with a single buffer", () =>
      withVim(async nvim => {
        const buffers = await nvim.call("nvim_list_bufs");

        assert.equal(buffers.toString(), [1].toString());
      }));

    it("it focuses a second buffer when the menu is opened", () =>
      withVim(async nvim => {
        await openActionMenu(nvim, ["One", "Two", "Three"]);

        const buffers = await nvim.call("nvim_list_bufs");
        const currentBuffer = await nvim.call("nvim_get_current_buf");

        assert.equal(buffers.toString(), [1, 2].toString());
        assert.equal(currentBuffer, 2);
      }));

    it("focuses the original buffer when the menu is closed", () =>
      withVim(async nvim => {
        const originalBuffer = await nvim.call("nvim_get_current_buf");

        await openActionMenu(nvim, ["One", "Two", "Three"]);
        const menuBuffer = await nvim.call("nvim_get_current_buf");

        await nvim.call("feedkeys", [ESC]);
        const currentBuffer = await nvim.call("nvim_get_current_buf");

        assert.equal(currentBuffer, originalBuffer);
        assert.notEqual(originalBuffer, menuBuffer);
      }));
  });

  describe("custom icon", () => {
    it("can use a custom character as an icon", () =>
      withVim(async nvim => {
        const icon = {
          character: "!",
          foreground: "red"
        };

        await nvim.command(
          `execute('call actionmenu#open(["One", "Two", "Three"], "TestCallback", { "icon": ${JSON.stringify(
            icon
          )} })')`
        );

        const line = await nvim.getLine();
        assert.equal(line, "One!");
      }));
  });

  describe("callback", () => {
    describe("when an item is not selected", () => {
      it("returns -1 index with null", () =>
        withVim(async nvim => {
          await nvim.command(
            `execute("call actionmenu#open(['One', 'Two', 'Three'], 'TestCallback')")`
          );

          await nvim.call("feedkeys", [ESC]);
          const {index, item} = await callbackResult(nvim);

          assert.equal(index, -1);
          assert.equal(item, 0);
        }));
    });

    describe("when an item is selected", () => {
      it("returns the selected index and item", () =>
        withVim(async nvim => {
          await openActionMenu(nvim, ["One", "Two", "Three"]);

          await nvim.call("feedkeys", [ENTER]);

          const {index, item} = await callbackResult(nvim);

          assert.equal(index, 0);
          assert.equal(item, "One");
        }));

      it("returns the selected index and complex item", () =>
        withVim(async nvim => {
          await openActionMenu(nvim, [{word: "One", user_data: "Foo"}]);

          await nvim.call("feedkeys", [ENTER]);

          const {index, item} = await callbackResult(nvim);

          assert.equal(index, 0);
          assert.equal(isComplexItem(item), true);
          if (isComplexItem(item)) {
            assert.equal(item.word, "One");
            assert.equal(item.user_data, "Foo");
          }
        }));

      it("invokes the callback once", async () =>
        withVim(async nvim => {
          const buffer = nvim.buffer;

          const selectAnItem = async () => {
            await openActionMenu(nvim, ["One"], '"TestPrintCallback"');
            await nvim.call("feedkeys", [ENTER]);
          };

          await selectAnItem();
          await selectAnItem();
          await selectAnItem();

          const lines = await buffer.getLines();
          assert.equal(lines.toString(), ["OneOneOne"].toString());
        }));

      it("clears the selected item on subsequent popups", async () =>
        withVim(async nvim => {
          const selectItemAndReturn = async () => {
            await openActionMenu(nvim, ["Foo"]);
            await nvim.call("feedkeys", [ENTER]);
            const {index} = await callbackResult(nvim);
            return index;
          };

          const selectedIndex = await selectItemAndReturn();
          assert.equal(selectedIndex, 0);

          const dontSelectAndReturn = async () => {
            await openActionMenu(nvim, ["Foo"]);
            await nvim.call("feedkeys", [ESC]);
            const {index} = await callbackResult(nvim);
            return index;
          };

          const notSelectedIndex = await dontSelectAndReturn();
          assert.equal(notSelectedIndex, -1);
        }));
    });
  });

  describe("shortcuts", () => {
    it("displays shortcut hints in menu items", () =>
      withVim(async nvim => {
        const items = [
          {word: "First", shortcut: "f"},
          {word: "Second", shortcut: "s"}
        ];

        await openActionMenu(nvim, items);

        // Get the completion items
        const completionItems = await nvim.call("complete_info", [["items"]]);
        const displayedItems = completionItems.items;

        // Check that shortcuts are displayed in the abbreviation
        assert.equal(displayedItems[0].abbr, "First [f]");
        assert.equal(displayedItems[1].abbr, "Second [s]");
      }));

    it("selects item when shortcut key is pressed", () =>
      withVim(async nvim => {
        const items = [
          {word: "First", shortcut: "f"},
          {word: "Second", shortcut: "s"},
          {word: "Third", shortcut: "t"}
        ];

        await openActionMenu(nvim, items);

        // Press the shortcut for "Second"
        await nvim.call("feedkeys", ["s"]);

        const {index, item} = await callbackResult(nvim);

        assert.equal(index, 1);
        assert.equal(isComplexItem(item), true);
        if (isComplexItem(item)) {
          assert.equal(item.word, "Second");
        }
      }));

    it("works with mixed shortcut and non-shortcut items", () =>
      withVim(async nvim => {
        const items = [
          {word: "First", shortcut: "f"},
          {word: "Second"},  // No shortcut
          {word: "Third", shortcut: "t"}
        ];

        await openActionMenu(nvim, items);

        // Press the shortcut for "Third"
        await nvim.call("feedkeys", ["t"]);

        const {index, item} = await callbackResult(nvim);

        assert.equal(index, 2);
        assert.equal(isComplexItem(item), true);
        if (isComplexItem(item)) {
          assert.equal(item.word, "Third");
        }
      }));

    it("shortcuts do not conflict with normal menu navigation", () =>
      withVim(async nvim => {
        const items = [
          {word: "First", shortcut: "f"},
          {word: "Second", shortcut: "s"}
        ];

        await openActionMenu(nvim, items);

        // Navigate down first, then use Enter to select
        await nvim.call("feedkeys", [`j${ENTER}`]);

        const {index, item} = await callbackResult(nvim);

        assert.equal(index, 1);
        assert.equal(isComplexItem(item), true);
        if (isComplexItem(item)) {
          assert.equal(item.word, "Second");
        }
      }));
  });
});
