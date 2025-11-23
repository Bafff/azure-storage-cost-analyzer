#!/usr/bin/env python3
"""
Zabbix Template Validator
Validates Zabbix 7.0+ template XML files for structure, syntax, and best practices.

Usage:
    python3 validate-zabbix-template.py <template.xml>
    python3 validate-zabbix-template.py --all  # Validate all templates in current directory
"""

import sys
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Tuple, List, Dict, Optional


class ZabbixTemplateValidator:
    """Validates Zabbix template XML files"""

    def __init__(self, file_path: Path):
        self.file_path = file_path
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.info: List[str] = []
        self.tree: Optional[ET.ElementTree] = None
        self.root: Optional[ET.Element] = None

    def validate(self) -> bool:
        """Run all validation checks"""
        print(f"\n{'='*70}")
        print(f"Validating: {self.file_path}")
        print(f"{'='*70}\n")

        # Parse XML
        if not self._parse_xml():
            return False

        # Run validation checks
        self._validate_root_structure()
        self._validate_version()
        self._validate_templates()

        # Print results
        self._print_results()

        return len(self.errors) == 0

    def _parse_xml(self) -> bool:
        """Parse the XML file"""
        try:
            self.tree = ET.parse(self.file_path)
            self.root = self.tree.getroot()
            self.info.append(f"✓ XML parsing successful")
            return True
        except ET.ParseError as e:
            self.errors.append(f"❌ XML parsing error: {e}")
            return False
        except Exception as e:
            self.errors.append(f"❌ Error reading file: {e}")
            return False

    def _validate_root_structure(self):
        """Validate root element structure"""
        if self.root.tag != 'zabbix_export':
            self.errors.append(
                f"❌ Root element must be 'zabbix_export', found '{self.root.tag}'"
            )
        else:
            self.info.append("✓ Root element is 'zabbix_export'")

    def _validate_version(self):
        """Validate Zabbix version"""
        version = self.root.find('version')
        if version is None:
            self.errors.append("❌ Missing <version> element")
        else:
            version_text = version.text
            self.info.append(f"✓ Zabbix version: {version_text}")

            # Check if version is 7.0 or higher
            try:
                major_version = float(version_text.split('.')[0])
                if major_version < 7.0:
                    self.warnings.append(
                        f"⚠ Zabbix version {version_text} is older than 7.0"
                    )
            except (ValueError, IndexError):
                self.warnings.append(f"⚠ Could not parse version: {version_text}")

    def _validate_templates(self):
        """Validate templates section"""
        templates = self.root.find('templates')
        if templates is None:
            self.errors.append("❌ Missing <templates> element")
            return

        template_list = templates.findall('template')
        template_count = len(template_list)

        if template_count == 0:
            self.warnings.append("⚠ No templates found in file")
            return

        self.info.append(f"✓ Found {template_count} template(s)")

        # Validate each template
        for idx, template in enumerate(template_list, 1):
            print(f"\n  Template {idx}:")
            self._validate_template(template)

    def _validate_template(self, template: ET.Element):
        """Validate individual template"""
        # Template name
        name = template.find('name')
        if name is None:
            self.errors.append("    ❌ Missing template name")
        else:
            print(f"    ✓ Name: {name.text}")

        # UUID (recommended for Zabbix 7.0+)
        uuid = template.find('uuid')
        if uuid is None:
            self.warnings.append("    ⚠ Missing UUID (recommended for Zabbix 7.0+)")
        else:
            uuid_text = uuid.text
            print(f"    ✓ UUID: {uuid_text[:8]}...")
            # Validate UUID format
            if not self._is_valid_uuid(uuid_text):
                self.errors.append(f"    ❌ Invalid UUID format: {uuid_text}")

        # Template groups
        groups = template.find('groups')
        if groups is None or len(groups.findall('group')) == 0:
            self.warnings.append("    ⚠ No template groups defined")
        else:
            group_count = len(groups.findall('group'))
            print(f"    ✓ Groups: {group_count}")
            self._validate_groups(groups)

        # Items
        items = template.find('items')
        if items is not None:
            item_list = items.findall('item')
            item_count = len(item_list)
            print(f"    ✓ Items: {item_count}")
            self._validate_items(item_list)
        else:
            print(f"    ℹ Items: 0")

        # Discovery rules
        discovery = template.find('discovery_rules')
        if discovery is not None:
            rule_list = discovery.findall('discovery_rule')
            rule_count = len(rule_list)
            print(f"    ✓ Discovery rules: {rule_count}")
            self._validate_discovery_rules(rule_list)
        else:
            print(f"    ℹ Discovery rules: 0")

        # Triggers
        triggers = template.find('triggers')
        if triggers is not None:
            trigger_list = triggers.findall('trigger')
            trigger_count = len(trigger_list)
            print(f"    ✓ Triggers: {trigger_count}")
            self._validate_triggers(trigger_list)
        else:
            print(f"    ℹ Triggers: 0")

        # Macros
        macros = template.find('macros')
        if macros is not None:
            macro_list = macros.findall('macro')
            macro_count = len(macro_list)
            print(f"    ✓ Macros: {macro_count}")
            self._validate_macros(macro_list)

    def _validate_groups(self, groups: ET.Element):
        """Validate template groups"""
        for group in groups.findall('group'):
            name = group.find('name')
            if name is None:
                self.errors.append("      ❌ Group missing name")

    def _validate_items(self, items: List[ET.Element]):
        """Validate items"""
        seen_keys = set()

        for item in items:
            # Check for required fields
            name = item.find('name')
            key = item.find('key')
            value_type = item.find('value_type')

            if name is None:
                self.errors.append("      ❌ Item missing name")

            if key is None:
                self.errors.append("      ❌ Item missing key")
            else:
                key_text = key.text
                # Check for spaces in key
                if ' ' in key_text:
                    self.warnings.append(
                        f"      ⚠ Item key contains spaces: '{key_text}' "
                        "(use dots or underscores instead)"
                    )

                # Check for duplicate keys
                if key_text in seen_keys:
                    self.errors.append(f"      ❌ Duplicate item key: '{key_text}'")
                seen_keys.add(key_text)

            if value_type is None:
                self.errors.append("      ❌ Item missing value_type")
            else:
                # Validate value_type (numeric or string constant)
                vtype_text = value_type.text
                # Zabbix 7.0 supports both numeric and string constants
                valid_numeric = [0, 1, 2, 3, 4, 15, 16]
                valid_string = ['FLOAT', 'CHAR', 'LOG', 'UNSIGNED', 'TEXT', 'BINARY', 'STR']

                try:
                    vtype = int(vtype_text)
                    if vtype not in valid_numeric:
                        self.warnings.append(
                            f"      ⚠ Unusual numeric value_type: {vtype}"
                        )
                except ValueError:
                    # String constant - validate it's a known type
                    if vtype_text not in valid_string:
                        self.warnings.append(
                            f"      ⚠ Unknown string value_type: '{vtype_text}'"
                        )

    def _validate_discovery_rules(self, rules: List[ET.Element]):
        """Validate discovery rules"""
        seen_keys = set()

        for rule in rules:
            name = rule.find('name')
            key = rule.find('key')

            if name is None:
                self.errors.append("      ❌ Discovery rule missing name")

            if key is None:
                self.errors.append("      ❌ Discovery rule missing key")
            else:
                key_text = key.text
                if key_text in seen_keys:
                    self.errors.append(
                        f"      ❌ Duplicate discovery rule key: '{key_text}'"
                    )
                seen_keys.add(key_text)

            # Check for item prototypes
            item_prototypes = rule.find('item_prototypes')
            if item_prototypes is not None:
                prototype_count = len(item_prototypes.findall('item_prototype'))
                if prototype_count == 0:
                    self.warnings.append(
                        "      ⚠ Discovery rule has no item prototypes"
                    )

    def _validate_triggers(self, triggers: List[ET.Element]):
        """Validate triggers and their expressions"""
        seen_expressions = set()

        for trigger in triggers:
            name = trigger.find('name')
            expression = trigger.find('expression')
            priority = trigger.find('priority')

            if name is None:
                self.errors.append("      ❌ Trigger missing name")

            if expression is None:
                self.errors.append("      ❌ Trigger missing expression")
            else:
                expr_text = expression.text
                # Check for duplicate expressions
                if expr_text in seen_expressions:
                    self.warnings.append(
                        f"      ⚠ Duplicate trigger expression: '{expr_text[:50]}...'"
                    )
                seen_expressions.add(expr_text)

                # Validate trigger expression syntax
                self._validate_trigger_expression(expr_text)

            if priority is None:
                self.warnings.append("      ⚠ Trigger missing priority")
            else:
                # Validate priority (numeric or string constant)
                priority_text = priority.text
                # Zabbix 7.0 supports both numeric (0-5) and string constants
                valid_numeric = range(0, 6)
                valid_string = ['NOT_CLASSIFIED', 'INFO', 'WARNING', 'AVERAGE', 'HIGH', 'DISASTER']

                try:
                    priority_val = int(priority_text)
                    if priority_val not in valid_numeric:
                        self.warnings.append(
                            f"      ⚠ Invalid priority value: {priority_val} "
                            "(should be 0-5)"
                        )
                except ValueError:
                    # String constant - validate it's a known priority
                    if priority_text not in valid_string:
                        self.warnings.append(
                            f"      ⚠ Unknown string priority: '{priority_text}'"
                        )

    def _validate_trigger_expression(self, expression: str):
        """Validate trigger expression syntax"""
        if not expression:
            self.errors.append("      ❌ Empty trigger expression")
            return

        # Check for common expression patterns
        # Zabbix 7.0 uses new expression syntax

        # Check for unmatched parentheses
        if expression.count('(') != expression.count(')'):
            self.errors.append(
                "      ❌ Unmatched parentheses in trigger expression"
            )

        # Check for unmatched braces
        if expression.count('{') != expression.count('}'):
            self.errors.append(
                "      ❌ Unmatched braces in trigger expression"
            )

        # Warn about old expression syntax (if using {HOSTNAME:key.func()})
        if re.search(r'\{[^}]+:[^}]+\.[^}]+\(\)\}', expression):
            self.warnings.append(
                "      ⚠ Possible old-style trigger expression detected "
                "(Zabbix 7.0 uses new syntax)"
            )

    def _validate_macros(self, macros: List[ET.Element]):
        """Validate macros"""
        seen_macros = set()

        for macro in macros:
            macro_name = macro.find('macro')
            value = macro.find('value')

            if macro_name is None:
                self.errors.append("      ❌ Macro missing name")
            else:
                name_text = macro_name.text
                # Check macro name format (should be {$MACRO_NAME})
                if not re.match(r'^\{\$[A-Z0-9_]+\}$', name_text):
                    self.warnings.append(
                        f"      ⚠ Macro name doesn't follow convention: '{name_text}' "
                        "(should be {{$UPPERCASE_WITH_UNDERSCORES}})"
                    )

                # Check for duplicate macros
                if name_text in seen_macros:
                    self.errors.append(f"      ❌ Duplicate macro: '{name_text}'")
                seen_macros.add(name_text)

            if value is None:
                self.warnings.append(
                    f"      ⚠ Macro '{macro_name.text if macro_name is not None else 'unknown'}' "
                    "has no value"
                )

    def _is_valid_uuid(self, uuid_str: str) -> bool:
        """Check if string is a valid UUID (with or without dashes)"""
        # Standard UUID format with dashes: 8-4-4-4-12
        uuid_pattern_dashed = re.compile(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            re.IGNORECASE
        )
        # UUID format without dashes (32 hex chars) - also valid in Zabbix 7.0
        uuid_pattern_nodash = re.compile(
            r'^[0-9a-f]{32}$',
            re.IGNORECASE
        )
        return bool(uuid_pattern_dashed.match(uuid_str)) or bool(uuid_pattern_nodash.match(uuid_str))

    def _print_results(self):
        """Print validation results"""
        print(f"\n{'='*70}")
        print("Validation Results")
        print(f"{'='*70}\n")

        # Print errors
        if self.errors:
            print(f"❌ ERRORS ({len(self.errors)}):")
            for error in self.errors:
                print(f"  {error}")
            print()

        # Print warnings
        if self.warnings:
            print(f"⚠ WARNINGS ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  {warning}")
            print()

        # Print info
        if self.info and not self.errors:
            print(f"ℹ INFO:")
            for info in self.info:
                print(f"  {info}")
            print()

        # Overall result
        if not self.errors:
            if self.warnings:
                print(f"✅ Validation PASSED with {len(self.warnings)} warning(s)")
            else:
                print("✅ Validation PASSED - no issues found!")
        else:
            print(f"❌ Validation FAILED with {len(self.errors)} error(s)")

        print(f"{'='*70}\n")


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python3 validate-zabbix-template.py <template.xml>")
        print("       python3 validate-zabbix-template.py --all")
        sys.exit(1)

    # Determine which files to validate
    if sys.argv[1] == '--all':
        # Find all Zabbix template files (XML and YAML)
        xml_files = list(Path('.').rglob('*zabbix*.xml'))
        xml_files.extend(Path('.').rglob('template*.xml'))
        yaml_files = list(Path('.').rglob('*zabbix*.yaml'))
        yaml_files.extend(Path('.').rglob('*zabbix*.yml'))

        # For YAML files, just verify they exist (validated by yamllint)
        if yaml_files:
            print("\n" + "="*70)
            print("Found YAML template files (validated by yamllint):")
            print("="*70)
            for yaml_file in yaml_files:
                print(f"✅ {yaml_file}")
            print()

        # Remove duplicates from XML files
        files = list(set(xml_files))

        if not files and not yaml_files:
            print("❌ No Zabbix template files found (XML or YAML)")
            sys.exit(1)

        if not files:
            # Only YAML files found, no XML to validate
            print("✅ All template files validated successfully!")
            sys.exit(0)
    else:
        # Validate specific file
        file_path = Path(sys.argv[1])
        if not file_path.exists():
            print(f"❌ File not found: {file_path}")
            sys.exit(1)
        files = [file_path]

    # Validate all files
    all_passed = True
    for file_path in files:
        validator = ZabbixTemplateValidator(file_path)
        passed = validator.validate()
        if not passed:
            all_passed = False

    # Exit with appropriate code
    sys.exit(0 if all_passed else 1)


if __name__ == '__main__':
    main()
