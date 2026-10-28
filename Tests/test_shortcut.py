import copy
import json
import plistlib
import unittest

from tools.build_shortcut import TEMPLATE, validate


class ShortcutTemplateTests(unittest.TestCase):
    def test_template_wiring(self):
        workflow = json.loads(TEMPLATE.read_text())
        validate(workflow)
        self.assertEqual(plistlib.loads(plistlib.dumps(workflow)), workflow)

    def test_rejects_disconnected_image_and_extra_actions(self):
        original = json.loads(TEMPLATE.read_text())
        workflow = copy.deepcopy(original)
        workflow["WFWorkflowActions"][1]["WFWorkflowActionParameters"]["WFInput"]["Value"]["OutputUUID"] = "unconnected"
        with self.assertRaises(ValueError):
            validate(workflow)
        workflow = copy.deepcopy(original)
        workflow["WFWorkflowActions"].append(workflow["WFWorkflowActions"][0])
        with self.assertRaises(ValueError):
            validate(workflow)

    def test_rejects_device_specific_wallpaper_parameters(self):
        workflow = json.loads(TEMPLATE.read_text())
        workflow["WFWorkflowActions"][1]["WFWorkflowActionParameters"]["WFWallpaper"] = "device-specific"
        with self.assertRaises(ValueError):
            validate(workflow)

    def test_rejects_preview_crop_and_blur_that_interrupt_automatic_changes(self):
        original = json.loads(TEMPLATE.read_text())
        for key in ["WFWallpaperShowPreview", "WFWallpaperSmartCrop", "WFWallpaperLegibilityBlur"]:
            workflow = copy.deepcopy(original)
            workflow["WFWorkflowActions"][1]["WFWorkflowActionParameters"][key] = True
            with self.assertRaises(ValueError):
                validate(workflow)
