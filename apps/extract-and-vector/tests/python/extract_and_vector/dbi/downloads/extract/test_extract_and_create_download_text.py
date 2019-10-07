from extract_and_vector.dbi.downloads.extract import extract_and_create_download_text
from extract_and_vector.dbi.stories.extractor_arguments import PyExtractorArguments
from .setup_test_extract import TestExtractDB


class TestExtractAndCreateDownloadText(TestExtractDB):

    def test_extract_and_create_download_text(self):
        download_text = extract_and_create_download_text(
            db=self.db,
            download=self.test_download,
            extractor_args=PyExtractorArguments(),
        )

        assert download_text
        assert download_text['download_text'] == 'foo.'
        assert download_text['downloads_id'] == self.test_download['downloads_id']
