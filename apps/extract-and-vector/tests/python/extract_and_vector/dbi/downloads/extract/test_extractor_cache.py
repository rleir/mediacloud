# noinspection PyProtectedMember
from extract_and_vector.dbi.downloads.extract import _set_extractor_results_cache, _get_extractor_results_cache
from .setup_test_extract import TestExtractDB


class TestExtractorCache(TestExtractDB):

    def test_extractor_cache(self) -> None:
        """Test set and get for extract cache."""
        extractor_results = {'extracted_html': 'extracted html', 'extracted_text': 'extracted text'}
        _set_extractor_results_cache(self.db, self.test_download, extractor_results)
        got_results = _get_extractor_results_cache(self.db, self.test_download)
        assert got_results == extractor_results
